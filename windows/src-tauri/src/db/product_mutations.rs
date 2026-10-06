//! Confirmed product operations; one transaction covers every affected entity.
use super::{models::*, Database, DatabaseError, Result};
use crate::lexical::{pos_tokens, unicode::trim};
use rusqlite::params;
use serde::Deserialize;
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WordEdit {
    pub id: Option<Id>,
    pub book_id: Id,
    pub expression: String,
    pub reading: String,
    pub meaning_chinese: String,
    pub part_of_speech: String,
    pub jlpt_level: String,
    pub example_japanese: String,
    pub example_chinese: String,
    pub tags: Vec<String>,
    pub is_favorite: bool,
}
impl Database {
    pub(crate) fn product_transaction<T>(
        &self,
        operation: impl FnOnce(&Self) -> Result<T>,
    ) -> Result<T> {
        self.connection.execute_batch("SAVEPOINT product_write")?;
        match operation(self) {
            Ok(value) => match self.connection.execute_batch("RELEASE product_write") {
                Ok(()) => Ok(value),
                Err(e) => {
                    self.connection
                        .execute_batch("ROLLBACK TO product_write; RELEASE product_write")?;
                    Err(e.into())
                }
            },
            Err(error) => {
                self.connection
                    .execute_batch("ROLLBACK TO product_write; RELEASE product_write")?;
                Err(error)
            }
        }
    }
    pub fn reset_word(&self, id: Id, confirmed: bool, now: Timestamp) -> Result<()> {
        if !confirmed {
            return Err(DatabaseError::InvalidData("confirmation required"));
        }
        self.product_transaction(|db| {
            if db.fetch_word(id)?.is_none() {
                return Err(DatabaseError::InvalidData("word missing"));
            }
            db.reset_progress(id, now)?;
            db.delete_logs_for_word(id)?;
            Ok(())
        })
    }
    fn reset_progress(&self, id: Id, now: Timestamp) -> Result<()> {
        let mut p = self.fetch_progress(id)?.unwrap_or(LearningProgress {
            id: Id::new_local(),
            word_id: id,
            state: LearningState::New,
            due_at: now,
            interval_days: 0,
            review_count: 0,
            lapse_count: 0,
            last_reviewed_at: None,
            created_at: now,
            updated_at: now,
        });
        p.state = LearningState::New;
        p.due_at = now;
        p.interval_days = 0;
        p.review_count = 0;
        p.lapse_count = 0;
        p.last_reviewed_at = None;
        p.updated_at = now;
        self.upsert_progress(&p)
    }
    pub fn reset_book(&self, id: Id, confirmed: bool, now: Timestamp) -> Result<()> {
        if !confirmed {
            return Err(DatabaseError::InvalidData("confirmation required"));
        }
        self.product_transaction(|db| {
            let mut book = db
                .fetch_book(id)?
                .ok_or(DatabaseError::InvalidData("book missing"))?;
            for mut word in db.words_by_book(id)?.into_iter().filter(|w| !w.is_archived) {
                db.reset_progress(word.id, now)?;
                word.updated_at = now;
                db.upsert_word(&word)?;
            }
            book.updated_at = now;
            db.upsert_book(&book)
        })
    }
    pub fn edit_word(&self, edit: WordEdit, now: Timestamp) -> Result<Id> {
        if [
            edit.expression.as_str(),
            edit.reading.as_str(),
            edit.meaning_chinese.as_str(),
        ]
        .iter()
        .any(|s| trim(s).is_empty())
        {
            return Err(DatabaseError::InvalidData(
                "expression reading and meaning required",
            ));
        }
        self.product_transaction(|db|{
            if db.fetch_book(edit.book_id)?.is_none(){return Err(DatabaseError::InvalidData("book missing"))}
            let id=edit.id.unwrap_or_else(Id::new_local);
            let duplicate:bool=db.connection.query_row("SELECT EXISTS(SELECT 1 FROM vocabulary_words WHERE word_book_id=?1 AND japanese=?2 AND kana=?3 AND id!=?4)",params![edit.book_id,trim(&edit.expression),trim(&edit.reading),id],|r|r.get(0))?;
            if duplicate{return Err(DatabaseError::InvalidData("duplicate expression and reading in book"))}
            let mut word=match edit.id {Some(id)=>db.fetch_word(id)?.ok_or(DatabaseError::InvalidData("word missing"))?,None=>VocabularyWord{id,japanese:String::new(),kana:String::new(),chinese_meaning:String::new(),part_of_speech:String::new(),jlpt_level:String::new(),example_japanese:String::new(),example_chinese:String::new(),tags:vec![],created_at:now,updated_at:now,is_archived:false,is_favorite:false,loanword_source_term:None,loanword_source_language_code:None,loanword_is_wasei:false,loanword_is_partial:false,word_book_id:Some(edit.book_id),canonical_id:None,canonical_key:None}};
            if edit.id.is_some() && word.word_book_id!=Some(edit.book_id){return Err(DatabaseError::InvalidData("word book cannot change"))}
            if word.japanese!=trim(&edit.expression)||word.kana!=trim(&edit.reading){word.loanword_source_term=None;word.loanword_source_language_code=None;word.loanword_is_wasei=false;word.loanword_is_partial=false;}
            word.japanese=trim(&edit.expression).into();word.kana=trim(&edit.reading).into();word.chinese_meaning=trim(&edit.meaning_chinese).into();word.part_of_speech=pos_tokens(&edit.part_of_speech).join("/");word.jlpt_level=trim(&edit.jlpt_level).to_uppercase();word.example_japanese=trim(&edit.example_japanese).into();word.example_chinese=trim(&edit.example_chinese).into();word.tags=edit.tags.into_iter().map(|t|trim(&t).to_owned()).filter(|t|!t.is_empty()).fold(Vec::new(),|mut all,t|{if !all.contains(&t){all.push(t)}all});word.is_favorite=edit.is_favorite;word.updated_at=now;db.upsert_word(&word)?;
            if edit.id.is_none(){db.reset_progress(id,now)?;}Ok(id)
        })
    }
    pub fn delete_word(&self, id: Id, confirmed: bool) -> Result<()> {
        if !confirmed {
            return Err(DatabaseError::InvalidData("confirmation required"));
        }
        self.product_transaction(|db| {
            db.connection
                .execute("DELETE FROM vocabulary_words WHERE id=?1", [id])?;
            Ok(())
        })
    }
    pub fn edit_book(
        &self,
        id: Option<Id>,
        name: &str,
        description: &str,
        now: Timestamp,
    ) -> Result<Id> {
        if trim(name).is_empty() {
            return Err(DatabaseError::InvalidData("book name required"));
        }
        let mut book = match id {
            Some(id) => self
                .fetch_book(id)?
                .ok_or(DatabaseError::InvalidData("book missing"))?,
            None => WordBook {
                id: Id::new_local(),
                name: String::new(),
                book_description: String::new(),
                created_at: now,
                updated_at: now,
                is_built_in: false,
                canonical_id: None,
                canonical_key: None,
            },
        };
        if book.is_built_in {
            return Err(DatabaseError::InvalidData(
                "built-in book metadata is protected",
            ));
        }
        book.name = trim(name).into();
        book.book_description = trim(description).into();
        book.updated_at = now;
        self.upsert_book(&book)?;
        Ok(book.id)
    }
    pub fn delete_book(&self, id: Id, confirmed: bool) -> Result<()> {
        if !confirmed {
            return Err(DatabaseError::InvalidData("confirmation required"));
        }
        self.product_transaction(|db| {
            let book = db
                .fetch_book(id)?
                .ok_or(DatabaseError::InvalidData("book missing"))?;
            if book.is_built_in {
                return Err(DatabaseError::InvalidData(
                    "built-in book cannot be deleted",
                ));
            }
            db.connection
                .execute("DELETE FROM vocabulary_words WHERE word_book_id=?1", [id])?;
            db.connection
                .execute("DELETE FROM word_books WHERE id=?1", [id])?;
            Ok(())
        })
    }
}
