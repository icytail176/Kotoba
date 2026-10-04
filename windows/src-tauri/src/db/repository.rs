use super::models::*;
use super::{Database, DatabaseError, Result};
use rusqlite::{params, OptionalExtension, Row};

fn decode_tags(row: &Row<'_>, index: usize) -> rusqlite::Result<Vec<String>> {
    let text: String = row.get(index)?;
    serde_json::from_str(&text).map_err(|e| {
        rusqlite::Error::FromSqlConversionFailure(index, rusqlite::types::Type::Text, Box::new(e))
    })
}
fn decode_errors(row: &Row<'_>, index: usize) -> rusqlite::Result<Vec<ReviewErrorType>> {
    let text: String = row.get(index)?;
    if text.is_empty() {
        return Ok(Vec::new());
    }
    text.split(';')
        .map(|raw| ReviewErrorType::parse(raw).ok_or(rusqlite::Error::InvalidQuery))
        .collect()
}

fn read_word_books(row: &Row<'_>) -> rusqlite::Result<WordBook> {
    Ok(WordBook {
        id: row.get(0)?,
        name: row.get(1)?,
        book_description: row.get(2)?,
        created_at: row.get(3)?,
        updated_at: row.get(4)?,
        is_built_in: row.get(5)?,
    })
}

fn read_vocabulary_words(row: &Row<'_>) -> rusqlite::Result<VocabularyWord> {
    Ok(VocabularyWord {
        id: row.get(0)?,
        japanese: row.get(1)?,
        kana: row.get(2)?,
        chinese_meaning: row.get(3)?,
        part_of_speech: row.get(4)?,
        jlpt_level: row.get(5)?,
        example_japanese: row.get(6)?,
        example_chinese: row.get(7)?,
        tags: decode_tags(row, 8)?,
        created_at: row.get(9)?,
        updated_at: row.get(10)?,
        is_archived: row.get(11)?,
        is_favorite: row.get(12)?,
        loanword_source_term: row.get(13)?,
        loanword_source_language_code: row.get(14)?,
        loanword_is_wasei: row.get(15)?,
        loanword_is_partial: row.get(16)?,
        word_book_id: row.get(17)?,
    })
}

fn read_learning_progress(row: &Row<'_>) -> rusqlite::Result<LearningProgress> {
    Ok(LearningProgress {
        id: row.get(0)?,
        word_id: row.get(1)?,
        state: row.get(2)?,
        due_at: row.get(3)?,
        interval_days: row.get(4)?,
        review_count: row.get(5)?,
        lapse_count: row.get(6)?,
        last_reviewed_at: row.get(7)?,
        created_at: row.get(8)?,
        updated_at: row.get(9)?,
    })
}

fn read_review_logs(row: &Row<'_>) -> rusqlite::Result<ReviewLog> {
    Ok(ReviewLog {
        id: row.get(0)?,
        word_id: row.get(1)?,
        reviewed_at: row.get(2)?,
        rating: row.get(3)?,
        previous_state: row.get(4)?,
        next_state: row.get(5)?,
        previous_interval_days: row.get(6)?,
        next_interval_days: row.get(7)?,
        scheduled_due_at: row.get(8)?,
        error_types: decode_errors(row, 9)?,
        typed_answer: row.get(10)?,
        expected_answer: row.get(11)?,
        question_direction_raw_value: row.get(12)?,
        reading_wrong_count: row.get(13)?,
        spelling_wrong_count: row.get(14)?,
        repeated_wrong_count: row.get(15)?,
    })
}

impl Database {
    pub fn upsert_book(&self, item: &WordBook) -> Result<()> {
        self.connection.execute("INSERT INTO word_books (id,name,book_description,created_at,updated_at,is_built_in) VALUES (?1,?2,?3,?4,?5,?6) ON CONFLICT(id) DO UPDATE SET name=excluded.name,book_description=excluded.book_description,updated_at=excluded.updated_at,is_built_in=excluded.is_built_in", params![item.id, item.name, item.book_description, item.created_at, item.updated_at, item.is_built_in])?;
        Ok(())
    }
    pub fn fetch_book(&self, id: Id) -> Result<Option<WordBook>> {
        Ok(self.connection.query_row("SELECT id,name,book_description,created_at,updated_at,is_built_in FROM word_books WHERE id=?1", [id], read_word_books).optional()?)
    }
    pub fn list_books(&self) -> Result<Vec<WordBook>> {
        let mut query = self.connection.prepare("SELECT id,name,book_description,created_at,updated_at,is_built_in FROM word_books ORDER BY created_at,id")?;
        let records = query
            .query_map([], read_word_books)?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(records)
    }
    pub fn upsert_word(&self, item: &VocabularyWord) -> Result<()> {
        let tags = serde_json::to_string(&item.tags)?;
        self.connection.execute("INSERT INTO vocabulary_words (id,japanese,kana,chinese_meaning,part_of_speech,jlpt_level,example_japanese,example_chinese,tags,created_at,updated_at,is_archived,is_favorite,loanword_source_term,loanword_source_language_code,loanword_is_wasei,loanword_is_partial,word_book_id) VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16,?17,?18) ON CONFLICT(id) DO UPDATE SET japanese=excluded.japanese,kana=excluded.kana,chinese_meaning=excluded.chinese_meaning,part_of_speech=excluded.part_of_speech,jlpt_level=excluded.jlpt_level,example_japanese=excluded.example_japanese,example_chinese=excluded.example_chinese,tags=excluded.tags,updated_at=excluded.updated_at,is_archived=excluded.is_archived,is_favorite=excluded.is_favorite,loanword_source_term=excluded.loanword_source_term,loanword_source_language_code=excluded.loanword_source_language_code,loanword_is_wasei=excluded.loanword_is_wasei,loanword_is_partial=excluded.loanword_is_partial,word_book_id=excluded.word_book_id", params![item.id, item.japanese, item.kana, item.chinese_meaning, item.part_of_speech, item.jlpt_level, item.example_japanese, item.example_chinese, tags, item.created_at, item.updated_at, item.is_archived, item.is_favorite, item.loanword_source_term, item.loanword_source_language_code, item.loanword_is_wasei, item.loanword_is_partial, item.word_book_id])?;
        Ok(())
    }
    pub fn fetch_word(&self, id: Id) -> Result<Option<VocabularyWord>> {
        Ok(self.connection.query_row("SELECT id,japanese,kana,chinese_meaning,part_of_speech,jlpt_level,example_japanese,example_chinese,tags,created_at,updated_at,is_archived,is_favorite,loanword_source_term,loanword_source_language_code,loanword_is_wasei,loanword_is_partial,word_book_id FROM vocabulary_words WHERE id=?1", [id], read_vocabulary_words).optional()?)
    }
    pub fn words_by_book(&self, id: Id) -> Result<Vec<VocabularyWord>> {
        let mut query = self.connection.prepare("SELECT id,japanese,kana,chinese_meaning,part_of_speech,jlpt_level,example_japanese,example_chinese,tags,created_at,updated_at,is_archived,is_favorite,loanword_source_term,loanword_source_language_code,loanword_is_wasei,loanword_is_partial,word_book_id FROM vocabulary_words WHERE word_book_id=?1 ORDER BY created_at,id")?;
        let records = query
            .query_map([id], read_vocabulary_words)?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(records)
    }
    pub fn upsert_progress(&self, item: &LearningProgress) -> Result<()> {
        let changed = self.connection.execute("INSERT INTO learning_progress (id,word_id,state,due_at,interval_days,review_count,lapse_count,last_reviewed_at,created_at,updated_at) VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10) ON CONFLICT(id) DO UPDATE SET state=excluded.state,due_at=excluded.due_at,interval_days=excluded.interval_days,review_count=excluded.review_count,lapse_count=excluded.lapse_count,last_reviewed_at=excluded.last_reviewed_at,updated_at=excluded.updated_at WHERE learning_progress.word_id=excluded.word_id", params![item.id, item.word_id, item.state, item.due_at, item.interval_days, item.review_count, item.lapse_count, item.last_reviewed_at, item.created_at, item.updated_at])?;
        if changed != 1 {
            return Err(DatabaseError::InvalidData(
                "upsert would change progress ownership",
            ));
        }
        Ok(())
    }
    pub fn fetch_progress(&self, id: Id) -> Result<Option<LearningProgress>> {
        Ok(self.connection.query_row("SELECT id,word_id,state,due_at,interval_days,review_count,lapse_count,last_reviewed_at,created_at,updated_at FROM learning_progress WHERE word_id=?1", [id], read_learning_progress).optional()?)
    }
    /// Exact UTC cutoff for minute states; caller supplies end-of-local-day for review.
    /// This query is storage filtering, not a scheduler or a study queue.
    pub fn due_progress(
        &self,
        instant: Timestamp,
        review_day_end_exclusive: Timestamp,
    ) -> Result<Vec<LearningProgress>> {
        let mut query = self.connection.prepare("SELECT id,word_id,state,due_at,interval_days,review_count,lapse_count,last_reviewed_at,created_at,updated_at FROM learning_progress WHERE (state IN ('learning','relearning') AND due_at<=?1) OR (state='review' AND due_at<?2) ORDER BY due_at,id")?;
        let records = query
            .query_map(
                params![instant, review_day_end_exclusive],
                read_learning_progress,
            )?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(records)
    }
    pub fn insert_log(&self, item: &ReviewLog) -> Result<()> {
        let mut errors: Vec<_> = item.error_types.iter().map(|e| e.as_str()).collect();
        errors.sort_unstable();
        let errors = errors.join(";");
        self.connection.execute("INSERT INTO review_logs (id,word_id,reviewed_at,rating,previous_state,next_state,previous_interval_days,next_interval_days,scheduled_due_at,error_types,typed_answer,expected_answer,question_direction_raw_value,reading_wrong_count,spelling_wrong_count,repeated_wrong_count) VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16)", params![item.id, item.word_id, item.reviewed_at, item.rating, item.previous_state, item.next_state, item.previous_interval_days, item.next_interval_days, item.scheduled_due_at, errors, item.typed_answer, item.expected_answer, item.question_direction_raw_value, item.reading_wrong_count, item.spelling_wrong_count, item.repeated_wrong_count])?;
        Ok(())
    }
    pub fn recent_logs(&self, word_id: Id, limit: u32) -> Result<Vec<ReviewLog>> {
        let mut query = self.connection.prepare("SELECT id,word_id,reviewed_at,rating,previous_state,next_state,previous_interval_days,next_interval_days,scheduled_due_at,error_types,typed_answer,expected_answer,question_direction_raw_value,reading_wrong_count,spelling_wrong_count,repeated_wrong_count FROM review_logs WHERE word_id=?1 ORDER BY reviewed_at DESC,id LIMIT ?2")?;
        let records = query
            .query_map(params![word_id, limit], read_review_logs)?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(records)
    }
    /// For an explicitly confirmed reset operation; never exposed as a Phase 2 IPC command.
    pub fn delete_logs_for_word(&self, word_id: Id) -> Result<usize> {
        Ok(self
            .connection
            .execute("DELETE FROM review_logs WHERE word_id=?1", [word_id])?)
    }
}
