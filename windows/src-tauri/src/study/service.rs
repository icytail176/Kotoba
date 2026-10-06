use super::models::*;
use crate::{
    db::{models::*, Database},
    srs::{
        calendar::CalendarContext,
        models::{FormalRating, SrsError},
        service::{self, FormalRatingRequest},
    },
};

pub fn formal(
    db: &mut Database,
    request: FormalRequest,
    calendar: &CalendarContext,
) -> Result<FormalCommit> {
    let lapse_before = request
        .expected_progress
        .as_ref()
        .map_or(0, |p| p.lapse_count);
    let result = service::apply_formal_rating_transaction(
        db,
        FormalRatingRequest {
            word_id: request.word_id,
            expected_progress: request.expected_progress,
            rating: FormalRating(request.rating),
            now: request.now,
        },
        calendar,
    )?;
    Ok(FormalCommit {
        did_lapse: result.progress.lapse_count > lapse_before,
        progress: result.progress,
        log_id: result.log.id,
        automatic_mastery: result.automatic_mastery,
    })
}
/// Explicit override, never formal scheduling or a second log.
pub fn reinforcement_mastered(
    db: &mut Database,
    word: Id,
    expected: LearningProgress,
    now: Timestamp,
) -> Result<LearningProgress> {
    Ok(db.srs_transaction(|repository| {
        repository.require_active_word(word)?;
        let current = repository.progress(word)?.ok_or(SrsError::StaleProgress)?;
        if current != expected {
            return Err(SrsError::StaleProgress);
        }
        if current.state == LearningState::Suspended {
            return Err(SrsError::SuspendedWord);
        }
        let mut next = current;
        next.state = LearningState::Suspended;
        next.interval_days = 0;
        next.due_at = now;
        next.updated_at = now;
        repository.save_progress(&next)?;
        repository.touch_word(word, now)?;
        Ok(next)
    })?)
}
pub fn favorite(db: &mut Database, word: Id, expected: bool, now: Timestamp) -> Result<bool> {
    db.study_favorite(word, expected, now)
}
pub fn enrich(db: &mut Database, entries: Vec<Enrichment>) -> Result<()> {
    if entries.len() > 300 {
        return Err(StudyError::invalid());
    }
    db.study_enrich(&entries)
}
