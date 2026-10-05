//! Product-facing read DTOs. Never expose persistence/identity/learning fields.
use super::{models::Id, Database, DatabaseError, Result};
use rusqlite::{params, OptionalExtension, Row};

#[derive(Debug, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WordBookSummary {
    pub id: Id,
    pub name: String,
    pub jlpt_level: String,
    pub word_count: u32,
}
#[derive(Debug, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WordListItem {
    pub id: Id,
    pub expression: String,
    pub reading: String,
    pub meaning_chinese: String,
    pub book_id: Id,
    pub book_name: String,
    pub jlpt_level: String,
}
#[derive(Debug, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PagedWords {
    pub items: Vec<WordListItem>,
    pub total: u32,
    pub limit: u32,
    pub offset: u32,
}
#[derive(Debug, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LoanwordSource {
    pub source_term: String,
    pub language_name: Option<&'static str>,
    pub is_wasei: bool,
    pub is_partial: bool,
}
#[derive(Debug, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WordDetail {
    #[serde(flatten)]
    pub word: WordListItem,
    pub part_of_speech: String,
    pub example_japanese: String,
    pub example_chinese: String,
    pub tags: Vec<String>,
    pub loanword: Option<LoanwordSource>,
    pub learning_status: crate::srs::models::LearningStatusPresentation,
}
const JOIN: &str = "FROM vocabulary_words w JOIN word_books b ON b.id=w.word_book_id";
const BUILTIN: &str =
    "w.canonical_id IS NOT NULL AND b.is_built_in=1 AND b.canonical_id IS NOT NULL";
const COLUMNS: &str = "w.id,w.japanese,w.kana,w.chinese_meaning,b.id,b.name,w.jlpt_level";
fn item(row: &Row<'_>) -> rusqlite::Result<WordListItem> {
    Ok(WordListItem {
        id: row.get(0)?,
        expression: row.get(1)?,
        reading: row.get(2)?,
        meaning_chinese: row.get(3)?,
        book_id: row.get(4)?,
        book_name: row.get(5)?,
        jlpt_level: row.get(6)?,
    })
}
fn limit_valid(limit: u32) -> Result<()> {
    if !(1..=100).contains(&limit) {
        return Err(DatabaseError::InvalidData(
            "limit must be between 1 and 100",
        ));
    }
    Ok(())
}
// Mirrors current Mac presentation policy, without changing stored metadata.
pub(super) fn loanword(
    term: Option<String>,
    language: Option<String>,
    wasei: bool,
    partial: bool,
) -> Option<LoanwordSource> {
    let term = term?.trim().to_string();
    if term.is_empty() {
        return None;
    }
    let code = language
        .as_deref()
        .unwrap_or_default()
        .trim()
        .to_lowercase();
    let name = match code.as_str() {
        "zho" | "chi" | "zh" | "chinese" | "chinese-origin" | "sino" | "sino-origin" | "中文"
        | "汉语" | "漢語" | "中国語" => return None,
        "eng" | "en" => Some("英语"),
        "deu" | "ger" | "de" => Some("德语"),
        "fra" | "fre" | "fr" => Some("法语"),
        "nld" | "dut" | "nl" => Some("荷兰语"),
        "por" | "pt" => Some("葡萄牙语"),
        "ita" | "it" => Some("意大利语"),
        "spa" | "es" => Some("西班牙语"),
        "rus" | "ru" => Some("俄语"),
        "lat" | "la" => Some("拉丁语"),
        _ if wasei => None,
        _ => return None,
    };
    Some(LoanwordSource {
        source_term: term,
        language_name: name,
        is_wasei: wasei,
        is_partial: partial,
    })
}
impl Database {
    pub fn browse_books(&self) -> Result<Vec<WordBookSummary>> {
        Ok(self
            .list_builtin_word_books()?
            .into_iter()
            .map(|b| WordBookSummary {
                id: b.id,
                name: b.name,
                jlpt_level: b.jlpt_level,
                word_count: b.word_count,
            })
            .collect())
    }
    pub fn browse_words(&self, book: Option<Id>, limit: u32, offset: u32) -> Result<PagedWords> {
        limit_valid(limit)?;
        let filter = format!("{BUILTIN} AND (?1 IS NULL OR b.id=?1)");
        let total = self.connection.query_row(
            &format!("SELECT count(*) {JOIN} WHERE {filter}"),
            [book],
            |r| r.get(0),
        )?;
        let mut statement=self.connection.prepare(&format!("SELECT {COLUMNS} {JOIN} WHERE {filter} ORDER BY b.canonical_key DESC,w.canonical_key,w.id LIMIT ?2 OFFSET ?3"))?;
        let items = statement
            .query_map(params![book, limit, offset], item)?
            .collect::<rusqlite::Result<_>>()?;
        Ok(PagedWords {
            items,
            total,
            limit,
            offset,
        })
    }
    pub fn browse_search(&self, query: &str, limit: u32, offset: u32) -> Result<PagedWords> {
        limit_valid(limit)?;
        let query = query.trim();
        if query.chars().count() > 200 {
            return Err(DatabaseError::InvalidData(
                "search query exceeds 200 characters",
            ));
        }
        if query.is_empty() {
            return Ok(PagedWords {
                items: Vec::new(),
                total: 0,
                limit,
                offset,
            });
        }
        let escaped = query
            .replace('\\', "\\\\")
            .replace('%', "\\%")
            .replace('_', "\\_");
        let pattern = format!("%{escaped}%");
        let filter=format!("{BUILTIN} AND (w.japanese LIKE ?1 ESCAPE '\\' OR w.kana LIKE ?1 ESCAPE '\\' OR w.chinese_meaning LIKE ?1 ESCAPE '\\')");
        let total = self.connection.query_row(
            &format!("SELECT count(*) {JOIN} WHERE {filter}"),
            [&pattern],
            |r| r.get(0),
        )?;
        let mut statement=self.connection.prepare(&format!("SELECT {COLUMNS} {JOIN} WHERE {filter} ORDER BY b.canonical_key DESC,w.canonical_key,w.id LIMIT ?2 OFFSET ?3"))?;
        let items = statement
            .query_map(params![pattern, limit, offset], item)?
            .collect::<rusqlite::Result<_>>()?;
        Ok(PagedWords {
            items,
            total,
            limit,
            offset,
        })
    }
    pub fn word_detail(&self, id: Id) -> Result<Option<WordDetail>> {
        let sql=format!("SELECT {COLUMNS},w.part_of_speech,w.example_japanese,w.example_chinese,w.tags,w.loanword_source_term,w.loanword_source_language_code,w.loanword_is_wasei,w.loanword_is_partial,p.state {JOIN} LEFT JOIN learning_progress p ON p.word_id=w.id WHERE {BUILTIN} AND w.id=?1");
        let detail = self
            .connection
            .query_row(&sql, [id], |row| {
                let raw: String = row.get(10)?;
                let tags: Vec<String> = serde_json::from_str(&raw).map_err(|error| {
                    rusqlite::Error::FromSqlConversionFailure(
                        10,
                        rusqlite::types::Type::Text,
                        Box::new(error),
                    )
                })?;
                Ok(WordDetail {
                    word: item(row)?,
                    part_of_speech: row.get(7)?,
                    example_japanese: row.get(8)?,
                    example_chinese: row.get(9)?,
                    tags: tags
                        .into_iter()
                        .filter(|t| {
                            t != "eggrolls" && !t.starts_with("原词性:") && !t.starts_with("音调:")
                        })
                        .collect(),
                    loanword: loanword(row.get(11)?, row.get(12)?, row.get(13)?, row.get(14)?),
                    learning_status: crate::srs::models::LearningStatusPresentation::from_state(
                        row.get(15)?,
                    ),
                })
            })
            .optional()?;
        Ok(detail)
    }
}
