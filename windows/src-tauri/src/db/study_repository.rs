//! Session SQL; transitions remain in the scheduler/services.
use super::{models::*, Database};
use crate::study::models::*;
use rusqlite::params;
impl Database {
    pub(crate) fn study_card_detail(&self, word: &VocabularyWord) -> Result<super::WordDetail> {
        let book_id = word.word_book_id.ok_or_else(StudyError::invalid)?;
        let book = self.fetch_book(book_id)?.ok_or_else(StudyError::invalid)?;
        Ok(super::WordDetail {
            word: super::ui_reads::WordListItem {
                id: word.id,
                expression: word.japanese.clone(),
                reading: word.kana.clone(),
                meaning_chinese: word.chinese_meaning.clone(),
                book_id: book.id,
                book_name: book.name,
                jlpt_level: word.jlpt_level.clone(),
            },
            part_of_speech: word.part_of_speech.clone(),
            example_japanese: word.example_japanese.clone(),
            example_chinese: word.example_chinese.clone(),
            tags: word.tags.clone(),
            loanword: super::ui_reads::loanword(
                word.loanword_source_term.clone(),
                word.loanword_source_language_code.clone(),
                word.loanword_is_wasei,
                word.loanword_is_partial,
            ),
            learning_status: crate::srs::models::LearningStatusPresentation::from_state(
                self.srs_read().progress(word.id)?.map(|p| p.state),
            ),
        })
    }
    pub(crate) fn study_ids(
        &self,
        book: Id,
        kind: CardKind,
        now: Timestamp,
        day_end: Timestamp,
        limit: u32,
        random: bool,
    ) -> Result<Vec<Id>> {
        let predicate = match kind { CardKind::NewWord => "(p.id IS NULL OR p.state='new')", CardKind::DueReview => "((p.state IN ('learning','relearning') AND p.due_at<=?2) OR (p.state='review' AND p.due_at<?3))" };
        let order = if random {
            "random()"
        } else if kind == CardKind::DueReview {
            "p.due_at,w.created_at,w.japanese,w.id"
        } else {
            "w.created_at,w.japanese,w.id"
        };
        let mut stmt=self.connection.prepare(&format!("SELECT w.id FROM vocabulary_words w LEFT JOIN learning_progress p ON p.word_id=w.id WHERE w.is_archived=0 AND w.word_book_id=?1 AND {predicate} ORDER BY {order} LIMIT ?4"))?;
        let rows = stmt
            .query_map(params![book, now, day_end, limit], |r| r.get(0))?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(rows)
    }
    pub(crate) fn study_counts(
        &self,
        book: Id,
        now: Timestamp,
        day_end: Timestamp,
        timezone: String,
    ) -> Result<Availability> {
        Ok(self.connection.query_row("SELECT count(*),coalesce(sum(p.id IS NULL OR p.state='new'),0),coalesce(sum((p.state IN ('learning','relearning') AND p.due_at<=?2) OR (p.state='review' AND p.due_at<?3)),0),coalesce(sum(p.state IN ('learning','relearning','review')),0),coalesce(sum(p.state='suspended'),0) FROM vocabulary_words w LEFT JOIN learning_progress p ON p.word_id=w.id WHERE w.is_archived=0 AND w.word_book_id=?1",params![book,now,day_end],|r|Ok(Availability{total_count:r.get(0)?,new_count:r.get(1)?,due_count:r.get(2)?,reviewing_count:r.get(3)?,mastered_count:r.get(4)?,timezone}))?)
    }
    pub(crate) fn study_favorite(
        &mut self,
        word: Id,
        expected: bool,
        now: Timestamp,
    ) -> Result<bool> {
        let tx = self
            .connection
            .transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
        let changed=tx.execute("UPDATE vocabulary_words SET is_favorite=?1,updated_at=?2 WHERE id=?3 AND is_archived=0 AND is_favorite=?4",params![!expected,now,word,expected])?;
        if changed != 1 {
            return Err(StudyError {
                code: "stale",
                message: "收藏状态已发生变化，请重新打开本组学习。",
            });
        }
        tx.commit()?;
        Ok(!expected)
    }
    pub(crate) fn study_enrich(&mut self, entries: &[Enrichment]) -> Result<()> {
        let tx = self
            .connection
            .transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
        let mut seen = std::collections::HashSet::new();
        for entry in entries {
            if !seen.insert(entry.log_id)
                || entry.reading_wrong_count < 0
                || entry.spelling_wrong_count < 0
                || entry.reading_wrong_count > 1_000_000
                || entry.spelling_wrong_count > 1_000_000
            {
                return Err(StudyError::invalid());
            }
            let wrong = entry.reading_wrong_count > 0 || entry.spelling_wrong_count > 0;
            if wrong
                && (!matches!(
                    entry.question_direction_raw_value.as_deref(),
                    Some("meaningToExpression" | "expressionToReading")
                ) || entry.typed_answer.is_none()
                    || entry.expected_answer.is_none())
            {
                return Err(StudyError::invalid());
            }
            if !wrong
                && (entry.question_direction_raw_value.is_some()
                    || entry.typed_answer.is_some()
                    || entry.expected_answer.is_some())
            {
                return Err(StudyError::invalid());
            }
            if entry.typed_answer.as_ref().is_some_and(|v| v.len() > 65536)
                || entry
                    .expected_answer
                    .as_ref()
                    .is_some_and(|v| v.len() > 65536)
            {
                return Err(StudyError::invalid());
            }
            let previous: String = tx.query_row(
                "SELECT error_types FROM review_logs WHERE id=?1 AND word_id=?2",
                params![entry.log_id, entry.word_id],
                |r| r.get(0),
            )?;
            let mut errors: Vec<&str> = previous.split(';').filter(|s| !s.is_empty()).collect();
            for (count, kind, direction) in [
                (
                    entry.spelling_wrong_count,
                    "spelling",
                    "expressionDirection",
                ),
                (entry.reading_wrong_count, "reading", "readingDirection"),
            ] {
                if count > 0 {
                    for value in [kind, direction] {
                        if !errors.contains(&value) {
                            errors.push(value);
                        }
                    }
                }
            }
            errors.sort_unstable();
            let changed=tx.execute("UPDATE review_logs SET error_types=?1,typed_answer=?2,expected_answer=?3,question_direction_raw_value=?4,reading_wrong_count=?5,spelling_wrong_count=?6 WHERE id=?7 AND word_id=?8",params![errors.join(";"),entry.typed_answer,entry.expected_answer,entry.question_direction_raw_value,entry.reading_wrong_count,entry.spelling_wrong_count,entry.log_id,entry.word_id])?;
            if changed != 1 {
                return Err(StudyError::invalid());
            }
        }
        tx.commit()?;
        Ok(())
    }
}
