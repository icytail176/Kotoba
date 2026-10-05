//! SQL only. Domain transitions and orchestration live in srs/.
use super::{
    models::*,
    repository::{read_learning_progress, read_review_logs},
    Database,
};
use crate::srs::models::{Result, SrsError};
use rusqlite::{params, Connection, OptionalExtension, TransactionBehavior};

const PROGRESS:&str="p.id,p.word_id,p.state,p.due_at,p.interval_days,p.review_count,p.lapse_count,p.last_reviewed_at,p.created_at,p.updated_at";
const LOG:&str="id,word_id,reviewed_at,rating,previous_state,next_state,previous_interval_days,next_interval_days,scheduled_due_at,error_types,typed_answer,expected_answer,question_direction_raw_value,reading_wrong_count,spelling_wrong_count,repeated_wrong_count";
pub(crate) struct SrsRepository<'a> {
    connection: &'a Connection,
}
impl Database {
    pub(crate) fn srs_read(&self) -> SrsRepository<'_> {
        SrsRepository {
            connection: &self.connection,
        }
    }
    pub(crate) fn srs_transaction<T>(
        &mut self,
        work: impl FnOnce(&SrsRepository<'_>) -> Result<T>,
    ) -> Result<T> {
        let transaction = self
            .connection
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let result = work(&SrsRepository {
            connection: &transaction,
        })?;
        transaction.commit()?;
        Ok(result)
    }
}
impl SrsRepository<'_> {
    pub fn require_active_word(&self, word: Id) -> Result<()> {
        let archived: Option<bool> = self
            .connection
            .query_row(
                "SELECT is_archived FROM vocabulary_words WHERE id=?1",
                [word],
                |r| r.get(0),
            )
            .optional()?;
        match archived {
            None => Err(SrsError::MissingWord),
            Some(true) => Err(SrsError::ArchivedWord),
            Some(false) => Ok(()),
        }
    }
    pub fn progress(&self, word: Id) -> Result<Option<LearningProgress>> {
        Ok(self
            .connection
            .query_row(
                &format!("SELECT {PROGRESS} FROM learning_progress p WHERE p.word_id=?1"),
                [word],
                read_learning_progress,
            )
            .optional()?)
    }
    pub fn latest_formal_log(&self, word: Id) -> Result<Option<ReviewLog>> {
        // All existing rows are formal: spelling enriches a row; reinforcement
        // never creates one. Filtering nullable spelling columns would be wrong.
        Ok(self.connection.query_row(&format!("SELECT {LOG} FROM review_logs WHERE word_id=?1 ORDER BY reviewed_at DESC,id LIMIT 1"),[word],read_review_logs).optional()?)
    }
    pub fn recent_logs(&self, word: Id, limit: u32) -> Result<Vec<ReviewLog>> {
        if !(1..=100).contains(&limit) {
            return Err(SrsError::InvalidLimit);
        }
        let mut statement = self.connection.prepare(&format!(
            "SELECT {LOG} FROM review_logs WHERE word_id=?1 ORDER BY reviewed_at DESC,id LIMIT ?2"
        ))?;
        let rows = statement
            .query_map(params![word, limit], read_review_logs)?
            .collect::<rusqlite::Result<_>>()?;
        Ok(rows)
    }
    pub fn save_progress(&self, p: &LearningProgress) -> Result<()> {
        self.connection.execute("INSERT INTO learning_progress (id,word_id,state,due_at,interval_days,review_count,lapse_count,last_reviewed_at,created_at,updated_at) VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10) ON CONFLICT(word_id) DO UPDATE SET state=excluded.state,due_at=excluded.due_at,interval_days=excluded.interval_days,review_count=excluded.review_count,lapse_count=excluded.lapse_count,last_reviewed_at=excluded.last_reviewed_at,updated_at=excluded.updated_at",params![p.id,p.word_id,p.state,p.due_at,p.interval_days,p.review_count,p.lapse_count,p.last_reviewed_at,p.created_at,p.updated_at])?;
        Ok(())
    }
    pub fn insert_formal_log(&self, log: &ReviewLog) -> Result<()> {
        self.connection.execute("INSERT INTO review_logs (id,word_id,reviewed_at,rating,previous_state,next_state,previous_interval_days,next_interval_days,scheduled_due_at,error_types,typed_answer,expected_answer,question_direction_raw_value,reading_wrong_count,spelling_wrong_count,repeated_wrong_count) VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,NULL,NULL,NULL,0,0,0)",params![log.id,log.word_id,log.reviewed_at,log.rating,log.previous_state,log.next_state,log.previous_interval_days,log.next_interval_days,log.scheduled_due_at,if log.rating==ReviewRating::Again {"meaning"} else {""}])?;
        Ok(())
    }
    pub fn touch_word(&self, word: Id, now: Timestamp) -> Result<()> {
        self.connection.execute(
            "UPDATE vocabulary_words SET updated_at=?1 WHERE id=?2",
            params![now, word],
        )?;
        Ok(())
    }
    pub fn eligible_new(&self, book: Option<Id>, limit: u32, offset: u32) -> Result<Vec<Id>> {
        if !(1..=100).contains(&limit) {
            return Err(SrsError::InvalidLimit);
        }
        let mut statement=self.connection.prepare("SELECT w.id FROM vocabulary_words w LEFT JOIN learning_progress p ON p.word_id=w.id WHERE w.is_archived=0 AND (p.id IS NULL OR p.state='new') AND (?1 IS NULL OR w.word_book_id=?1) ORDER BY w.created_at,w.japanese,w.id LIMIT ?2 OFFSET ?3")?;
        let rows = statement
            .query_map(params![book, limit, offset], |r| r.get(0))?
            .collect::<rusqlite::Result<_>>()?;
        Ok(rows)
    }
    pub fn due(&self, now: Timestamp, day_end: Timestamp) -> Result<Vec<LearningProgress>> {
        let mut statement=self.connection.prepare(&format!("SELECT {PROGRESS} FROM learning_progress p JOIN vocabulary_words w ON w.id=p.word_id WHERE w.is_archived=0 AND ((p.state IN ('learning','relearning') AND p.due_at<=?1) OR (p.state='review' AND p.due_at<?2)) ORDER BY p.due_at,p.id"))?;
        let rows = statement
            .query_map(params![now, day_end], read_learning_progress)?
            .collect::<rusqlite::Result<_>>()?;
        Ok(rows)
    }
}
