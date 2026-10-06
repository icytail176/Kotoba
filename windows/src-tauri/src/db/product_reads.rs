//! Bounded SQLite product queries. Canonical metadata remains a persistence concern.
use super::{
    models::*,
    ui_reads::{loanword, LoanwordSource},
    Database, DatabaseError, Result,
};
use crate::lexical::{self, conjugation::Conjugation, Pitch};
use rusqlite::{functions::FunctionFlags, params, OptionalExtension};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub enum WordFilter {
    #[default]
    All,
    New,
    Review,
    Mastered,
    Favorite,
    Difficult,
}
#[derive(Debug, Clone, Copy, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub enum WordSort {
    #[default]
    DefaultOrder,
    RecentlyStudied,
    NextDue,
    LapseCount,
}
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WordQuery {
    pub book_id: Option<Id>,
    pub search: String,
    pub status: WordFilter,
    pub favorites_only: bool,
    pub jlpt: Option<String>,
    pub part_of_speech: Option<String>,
    pub tag: Option<String>,
    pub sort: WordSort,
    pub limit: u32,
    pub offset: u32,
}
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProductWord {
    pub id: Id,
    pub expression: String,
    pub reading: String,
    pub meaning_chinese: String,
    pub book_id: Option<Id>,
    pub book_name: String,
    pub jlpt_level: String,
    pub is_favorite: bool,
    pub learning_status: &'static str,
    pub is_difficult: bool,
    pub romaji: String,
}
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProductPage {
    pub items: Vec<ProductWord>,
    pub total: u32,
    pub limit: u32,
    pub offset: u32,
}
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProductBook {
    pub id: Id,
    pub name: String,
    pub book_description: String,
    pub is_built_in: bool,
    pub jlpt_level: String,
    pub word_count: u32,
    pub unlearned: u32,
    pub reviewing: u32,
    pub mastered: u32,
}
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProductDetail {
    #[serde(flatten)]
    pub word: ProductWord,
    pub part_of_speech: String,
    pub example_japanese: String,
    pub example_chinese: String,
    pub tags: Vec<String>,
    pub editing_tags: Vec<String>,
    pub pitch: Option<Pitch>,
    pub conjugation: Option<Conjugation>,
    pub loanword: Option<LoanwordSource>,
    pub progress: Option<LearningProgress>,
    pub history_count: u32,
}
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FilterOptions {
    pub parts_of_speech: Vec<String>,
    pub tags: Vec<String>,
}

pub(super) fn register(connection: &rusqlite::Connection) -> rusqlite::Result<()> {
    let flags = FunctionFlags::SQLITE_UTF8 | FunctionFlags::SQLITE_DETERMINISTIC;
    connection.create_scalar_function("search_key", 1, flags, |ctx| {
        Ok(lexical::unicode::search_key(&ctx.get::<String>(0)?))
    })?;
    connection.create_scalar_function("romaji", 1, flags, |ctx| {
        Ok(lexical::romaji(&ctx.get::<String>(0)?))
    })?;
    connection.create_scalar_function("has_pos", 2, flags, |ctx| {
        Ok(lexical::pos_tokens(&ctx.get::<String>(0)?).contains(&ctx.get::<String>(1)?))
    })?;
    Ok(())
}
impl Database {
    pub fn product_words(&self, query: WordQuery) -> Result<ProductPage> {
        if !(1..=100).contains(&query.limit) || query.search.chars().count() > 200 {
            return Err(DatabaseError::InvalidData("invalid page or search length"));
        }
        let status = match query.status {
            WordFilter::All => "1",
            WordFilter::New => "(p.state IS NULL OR p.state='new')",
            WordFilter::Review => "p.state IN ('learning','relearning','review')",
            WordFilter::Mastered => "p.state='suspended'",
            WordFilter::Favorite => "w.is_favorite=1",
            WordFilter::Difficult => "p.lapse_count>=2",
        };
        let order = match query.sort { WordSort::DefaultOrder=>"",WordSort::RecentlyStudied=>"p.last_reviewed_at DESC,",WordSort::NextDue=>"CASE WHEN p.state IN ('learning','relearning','review') THEN 0 ELSE 1 END,CASE WHEN p.state IN ('learning','relearning','review') THEN p.due_at END,",WordSort::LapseCount=>"coalesce(p.lapse_count,0) DESC," };
        let from=format!("FROM vocabulary_words w LEFT JOIN word_books b ON b.id=w.word_book_id LEFT JOIN learning_progress p ON p.word_id=w.id WHERE w.is_archived=0 AND {status} AND (?1 IS NULL OR w.word_book_id=?1) AND (?2='' OR instr(search_key(w.japanese),?2)>0 OR instr(search_key(w.kana),?2)>0 OR instr(search_key(w.chinese_meaning),?2)>0 OR instr(search_key(coalesce(w.loanword_source_term,'')),?2)>0 OR instr(search_key(romaji(w.kana)),?2)>0) AND (?3=0 OR w.is_favorite=1) AND (?4 IS NULL OR w.jlpt_level=?4) AND (?5 IS NULL OR has_pos(w.part_of_speech,?5)) AND (?6 IS NULL OR EXISTS(SELECT 1 FROM json_each(w.tags) WHERE value=?6))");
        let search = lexical::unicode::search_key(&query.search);
        let args = params![
            query.book_id,
            search,
            query.favorites_only,
            query.jlpt,
            query.part_of_speech,
            query.tag
        ];
        let total = self
            .connection
            .query_row(&format!("SELECT count(*) {from}"), args, |r| r.get(0))?;
        let mut statement=self.connection.prepare(&format!("SELECT w.id,w.japanese,w.kana,w.chinese_meaning,w.word_book_id,coalesce(b.name,'未分类'),w.jlpt_level,w.is_favorite,p.state,coalesce(p.lapse_count,0) {from} ORDER BY {order} w.japanese,w.kana,w.id LIMIT ?7 OFFSET ?8"))?;
        let items = statement
            .query_map(
                params![
                    query.book_id,
                    search,
                    query.favorites_only,
                    query.jlpt,
                    query.part_of_speech,
                    query.tag,
                    query.limit,
                    query.offset
                ],
                |r| {
                    let reading: String = r.get(2)?;
                    let state: Option<LearningState> = r.get(8)?;
                    Ok(ProductWord {
                        id: r.get(0)?,
                        expression: r.get(1)?,
                        romaji: lexical::romaji(&reading),
                        reading,
                        meaning_chinese: r.get(3)?,
                        book_id: r.get(4)?,
                        book_name: r.get(5)?,
                        jlpt_level: r.get(6)?,
                        is_favorite: r.get(7)?,
                        learning_status: status_label(state),
                        is_difficult: r.get::<_, i64>(9)? >= 2,
                    })
                },
            )?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(ProductPage {
            items,
            total,
            limit: query.limit,
            offset: query.offset,
        })
    }
    pub fn product_books(&self) -> Result<Vec<ProductBook>> {
        let mut stmt=self.connection.prepare("SELECT b.id,b.name,b.book_description,b.is_built_in,CASE WHEN b.is_built_in=1 THEN upper(substr(b.canonical_key,6)) ELSE '' END,count(w.id),sum(CASE WHEN w.id IS NOT NULL AND (p.state IS NULL OR p.state='new') THEN 1 ELSE 0 END),sum(CASE WHEN p.state IN ('learning','relearning','review') THEN 1 ELSE 0 END),sum(CASE WHEN p.state='suspended' THEN 1 ELSE 0 END) FROM word_books b LEFT JOIN vocabulary_words w ON w.word_book_id=b.id AND w.is_archived=0 LEFT JOIN learning_progress p ON p.word_id=w.id GROUP BY b.id ORDER BY b.is_built_in DESC,b.canonical_key DESC,b.created_at,b.id")?;
        let books = stmt
            .query_map([], |r| {
                Ok(ProductBook {
                    id: r.get(0)?,
                    name: r.get(1)?,
                    book_description: r.get(2)?,
                    is_built_in: r.get(3)?,
                    jlpt_level: r.get(4)?,
                    word_count: r.get(5)?,
                    unlearned: r.get(6)?,
                    reviewing: r.get(7)?,
                    mastered: r.get(8)?,
                })
            })?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(books)
    }
    pub fn product_detail(&self, id: Id) -> Result<Option<ProductDetail>> {
        let Some(w) = self.fetch_word(id)?.filter(|w| !w.is_archived) else {
            return Ok(None);
        };
        let progress = self.fetch_progress(id)?;
        let book_name = match w.word_book_id {
            Some(book) => self
                .fetch_book(book)?
                .map(|b| b.name)
                .unwrap_or_else(|| "未分类".into()),
            None => "未分类".into(),
        };
        let history_count = self.connection.query_row(
            "SELECT count(*) FROM review_logs WHERE word_id=?1",
            [id],
            |r| r.get(0),
        )?;
        Ok(Some(ProductDetail {
            word: ProductWord {
                id,
                expression: w.japanese.clone(),
                reading: w.kana.clone(),
                romaji: lexical::romaji(&w.kana),
                meaning_chinese: w.chinese_meaning,
                book_id: w.word_book_id,
                book_name,
                jlpt_level: w.jlpt_level,
                is_favorite: w.is_favorite,
                learning_status: status_label(progress.as_ref().map(|p| p.state)),
                is_difficult: progress.as_ref().is_some_and(|p| p.lapse_count >= 2),
            },
            part_of_speech: w.part_of_speech.clone(),
            example_japanese: w.example_japanese,
            example_chinese: w.example_chinese,
            pitch: lexical::pitch(&w.tags),
            conjugation: lexical::conjugation::generate(&w.japanese, &w.kana, &w.part_of_speech),
            editing_tags: w.tags.clone(),
            tags: w
                .tags
                .into_iter()
                .filter(|t| t != "eggrolls" && !t.starts_with("原词性:") && !t.starts_with("音调:"))
                .collect(),
            loanword: loanword(
                w.loanword_source_term,
                w.loanword_source_language_code,
                w.loanword_is_wasei,
                w.loanword_is_partial,
            ),
            progress,
            history_count,
        }))
    }
    pub fn filter_options(&self) -> Result<FilterOptions> {
        let mut pos = std::collections::BTreeSet::new();
        let mut stmt = self
            .connection
            .prepare("SELECT DISTINCT part_of_speech FROM vocabulary_words WHERE is_archived=0")?;
        for raw in stmt.query_map([], |r| r.get::<_, String>(0))? {
            pos.extend(lexical::pos_tokens(&raw?));
        }
        let mut stmt=self.connection.prepare("SELECT DISTINCT value FROM vocabulary_words,json_each(vocabulary_words.tags) WHERE is_archived=0 AND value!='eggrolls' AND value NOT LIKE '音调:%' AND value NOT LIKE '原词性:%' ORDER BY value")?;
        let tags = stmt
            .query_map([], |r| r.get(0))?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(FilterOptions {
            parts_of_speech: pos.into_iter().collect(),
            tags,
        })
    }
    pub fn random_example(&self, book: Option<Id>) -> Result<Option<ProductDetail>> {
        let id=self.connection.query_row("SELECT id FROM vocabulary_words WHERE is_archived=0 AND trim(example_japanese)!='' AND trim(example_chinese)!='' AND (?1 IS NULL OR word_book_id=?1) ORDER BY CASE WHEN instr(example_japanese,japanese)>0 THEN 0 ELSE 1 END,random() LIMIT 1",[book],|r|r.get::<_,Id>(0)).optional()?;
        id.map(|id| self.product_detail(id))
            .transpose()
            .map(Option::flatten)
    }
}
fn status_label(state: Option<LearningState>) -> &'static str {
    match state {
        None | Some(LearningState::New) => "unlearned",
        Some(LearningState::Suspended) => "mastered",
        _ => "reviewing",
    }
}
