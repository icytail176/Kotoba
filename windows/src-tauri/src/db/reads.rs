use super::{models::*, repository::read_vocabulary_words, Database, DatabaseError, Result};
use rusqlite::{params, OptionalExtension};

const WORD_COLUMNS:&str="id,japanese,kana,chinese_meaning,part_of_speech,jlpt_level,example_japanese,example_chinese,tags,created_at,updated_at,is_archived,is_favorite,loanword_source_term,loanword_source_language_code,loanword_is_wasei,loanword_is_partial,word_book_id,canonical_id,canonical_key";
#[derive(Debug, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BookSummary {
    pub id: Id,
    pub canonical_id: Id,
    pub canonical_key: String,
    pub name: String,
    pub jlpt_level: String,
    pub word_count: u32,
    pub archived_word_count: u32,
}
#[derive(Debug, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WordPage {
    pub items: Vec<VocabularyWord>,
    pub total: u32,
    pub limit: u32,
    pub offset: u32,
}
fn page_limit(limit: u32) -> Result<()> {
    if !(1..=100).contains(&limit) {
        Err(DatabaseError::InvalidData(
            "limit must be between 1 and 100",
        ))
    } else {
        Ok(())
    }
}
impl Database {
    pub fn list_builtin_word_books(&self) -> Result<Vec<BookSummary>> {
        let mut query=self.connection.prepare("SELECT b.id,b.canonical_id,b.canonical_key,b.name,upper(substr(b.canonical_key,6)),count(w.id),coalesce(sum(w.is_archived),0) FROM word_books b LEFT JOIN vocabulary_words w ON w.word_book_id=b.id AND w.canonical_id IS NOT NULL WHERE b.is_built_in=1 AND b.canonical_id IS NOT NULL GROUP BY b.id ORDER BY b.canonical_key DESC")?;
        let records = query
            .query_map([], |r| {
                Ok(BookSummary {
                    id: r.get(0)?,
                    canonical_id: r.get(1)?,
                    canonical_key: r.get(2)?,
                    name: r.get(3)?,
                    jlpt_level: r.get(4)?,
                    word_count: r.get(5)?,
                    archived_word_count: r.get(6)?,
                })
            })?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(records)
    }
    pub fn get_word_book_summary(&self, id: Id) -> Result<Option<BookSummary>> {
        Ok(self
            .list_builtin_word_books()?
            .into_iter()
            .find(|b| b.id == id))
    }
    pub fn get_word_by_canonical_id(&self, id: Id) -> Result<Option<VocabularyWord>> {
        Ok(self
            .connection
            .query_row(
                &format!("SELECT {WORD_COLUMNS} FROM vocabulary_words WHERE canonical_id=?1"),
                [id],
                read_vocabulary_words,
            )
            .optional()?)
    }
    pub fn list_words(&self, book: Id, limit: u32, offset: u32) -> Result<WordPage> {
        page_limit(limit)?;
        let total=self.connection.query_row("SELECT count(*) FROM vocabulary_words WHERE word_book_id=?1 AND canonical_id IS NOT NULL",[book],|r|r.get(0))?;
        let mut query=self.connection.prepare(&format!("SELECT {WORD_COLUMNS} FROM vocabulary_words WHERE word_book_id=?1 AND canonical_id IS NOT NULL ORDER BY canonical_key,id LIMIT ?2 OFFSET ?3"))?;
        let items = query
            .query_map(params![book, limit, offset], read_vocabulary_words)?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(WordPage {
            items,
            total,
            limit,
            offset,
        })
    }
    /// Literal substring search, never treats user '%'/'_' as wildcards.
    pub fn search_words(&self, text: &str, limit: u32, offset: u32) -> Result<WordPage> {
        page_limit(limit)?;
        let text = text.trim();
        if text.chars().count() > 200 {
            return Err(DatabaseError::InvalidData(
                "search query exceeds 200 characters",
            ));
        }
        if text.is_empty() {
            return Ok(WordPage {
                items: Vec::new(),
                total: 0,
                limit,
                offset,
            });
        }
        let escaped = text
            .replace('\\', "\\\\")
            .replace('%', "\\%")
            .replace('_', "\\_");
        let pattern = format!("%{escaped}%");
        let filter="canonical_id IS NOT NULL AND (japanese LIKE ?1 ESCAPE '\\' OR kana LIKE ?1 ESCAPE '\\' OR chinese_meaning LIKE ?1 ESCAPE '\\')";
        let total = self.connection.query_row(
            &format!("SELECT count(*) FROM vocabulary_words WHERE {filter}"),
            [&pattern],
            |r| r.get(0),
        )?;
        let mut query=self.connection.prepare(&format!("SELECT {WORD_COLUMNS} FROM vocabulary_words WHERE {filter} ORDER BY canonical_key,id LIMIT ?2 OFFSET ?3"))?;
        let items = query
            .query_map(params![pattern, limit, offset], read_vocabulary_words)?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(WordPage {
            items,
            total,
            limit,
            offset,
        })
    }
}
