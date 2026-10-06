use super::models::*;
use crate::{
    db::{models::*, Database},
    srs::{calendar::CalendarContext, service::fetch_progress},
};

pub struct QueuePolicy {
    pub new_limit: u32,
    pub review_limit: u32,
    pub randomizes: bool,
}
impl Default for QueuePolicy {
    fn default() -> Self {
        Self {
            new_limit: 10,
            review_limit: 20,
            randomizes: true,
        }
    }
}
pub fn start(
    db: &Database,
    book: Id,
    mode: SessionMode,
    now: Timestamp,
    calendar: &CalendarContext,
    policy: QueuePolicy,
    timezone: String,
) -> Result<SessionStart> {
    if db.fetch_book(book)?.is_none() {
        return Err(StudyError::invalid());
    }
    let day_end = calendar.day_end_exclusive(now)?;
    let mut selected = Vec::new();
    for (kind, limit, enabled) in [
        (
            CardKind::DueReview,
            policy.review_limit.clamp(1, 200),
            mode != SessionMode::NewWordsOnly,
        ),
        (
            CardKind::NewWord,
            policy.new_limit.clamp(1, 100),
            mode != SessionMode::DueReviewsOnly,
        ),
    ] {
        if enabled {
            for id in db.study_ids(book, kind, now, day_end, limit, policy.randomizes)? {
                selected.push((id, kind));
            }
        }
    }
    if policy.randomizes {
        selected.sort_by_cached_key(|_| uuid::Uuid::new_v4());
    }
    let mut cards = Vec::with_capacity(selected.len());
    for (id, kind) in selected {
        let raw = db.fetch_word(id)?.ok_or_else(StudyError::invalid)?;
        let word = db.study_card_detail(&raw)?;
        cards.push(StudyCard {
            word,
            kind,
            expected_progress: fetch_progress(db, id)?,
            is_favorite: raw.is_favorite,
        });
    }
    Ok(SessionStart { cards, timezone })
}
pub fn availability(
    db: &Database,
    book: Id,
    now: Timestamp,
    calendar: &CalendarContext,
    timezone: String,
) -> Result<Availability> {
    if db.fetch_book(book)?.is_none() {
        return Err(StudyError::invalid());
    }
    db.study_counts(book, now, calendar.day_end_exclusive(now)?, timezone)
}
