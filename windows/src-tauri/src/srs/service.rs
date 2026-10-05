use super::{calendar::CalendarContext, models::*, scheduler};
use crate::db::{models::*, Database};

pub struct FormalRatingRequest {
    pub word_id: Id,
    /// Exact snapshot fetched by the caller; None means no persisted progress.
    /// A duplicate callback carrying this snapshot fails after the first commit.
    pub expected_progress: Option<LearningProgress>,
    pub rating: FormalRating,
    pub now: Timestamp,
}
pub struct CommittedReview {
    pub progress: LearningProgress,
    pub log: FormalLogDto,
    pub automatic_mastery: bool,
}
#[derive(Debug, Clone, Copy)]
pub(crate) enum Checkpoint {
    AfterProgress,
    AfterLog,
}

fn initial(word: Id, now: Timestamp) -> LearningProgress {
    LearningProgress {
        id: Id::new_local(),
        word_id: word,
        state: LearningState::New,
        due_at: now,
        interval_days: 0,
        review_count: 0,
        lapse_count: 0,
        last_reviewed_at: None,
        created_at: now,
        updated_at: now,
    }
}
pub fn fetch_progress(db: &Database, word: Id) -> Result<Option<LearningProgress>> {
    db.srs_read().require_active_word(word)?;
    db.srs_read().progress(word)
}
pub fn apply_formal_rating_transaction(
    db: &mut Database,
    request: FormalRatingRequest,
    calendar: &CalendarContext,
) -> Result<CommittedReview> {
    apply(db, request, calendar, |_| Ok(()))
}
pub(crate) fn apply(
    db: &mut Database,
    request: FormalRatingRequest,
    calendar: &CalendarContext,
    checkpoint: impl Fn(Checkpoint) -> Result<()>,
) -> Result<CommittedReview> {
    db.srs_transaction(|repository| {
        repository.require_active_word(request.word_id)?;
        let current = repository.progress(request.word_id)?;
        if current != request.expected_progress {
            return Err(SrsError::StaleProgress);
        }
        let previous = current.unwrap_or_else(|| initial(request.word_id, request.now));
        if previous.state == LearningState::Suspended {
            return Err(SrsError::SuspendedWord);
        }
        // A timestamp-only latest-log lookup is ambiguous at equal microseconds.
        // ORDER BY reviewed_at DESC,id is the existing index's deterministic order.
        let previous_log = repository.latest_formal_log(request.word_id)?;
        let scheduled = scheduler::schedule(
            &ProgressSnapshot::from(&previous),
            request.rating,
            request.now,
            previous_log.map(|l| l.rating),
            false,
            calendar,
        )?;
        let mut next = previous.clone();
        next.state = scheduled.state;
        next.interval_days = scheduled.interval_days;
        next.due_at = scheduled.due_at;
        next.review_count = scheduled.review_count;
        next.lapse_count = scheduled.lapse_count;
        next.last_reviewed_at = Some(request.now);
        next.updated_at = request.now;
        let log = ReviewLog {
            id: Id::new_local(),
            word_id: request.word_id,
            reviewed_at: request.now,
            rating: request.rating.0,
            previous_state: previous.state,
            next_state: next.state,
            previous_interval_days: previous.interval_days,
            next_interval_days: next.interval_days,
            scheduled_due_at: next.due_at,
            error_types: if request.rating.0 == ReviewRating::Again {
                vec![ReviewErrorType::Meaning]
            } else {
                vec![]
            },
            typed_answer: None,
            expected_answer: None,
            question_direction_raw_value: None,
            reading_wrong_count: 0,
            spelling_wrong_count: 0,
            repeated_wrong_count: 0,
        };
        repository.save_progress(&next)?;
        checkpoint(Checkpoint::AfterProgress)?;
        repository.insert_formal_log(&log)?;
        checkpoint(Checkpoint::AfterLog)?;
        repository.touch_word(request.word_id, request.now)?;
        Ok(CommittedReview {
            progress: next,
            log: log.into(),
            automatic_mastery: scheduled.automatic_mastery,
        })
    })
}
pub fn fetch_latest_formal_log_for_word(db: &Database, word: Id) -> Result<Option<FormalLogDto>> {
    Ok(db.srs_read().latest_formal_log(word)?.map(Into::into))
}
pub fn recent_review_logs(db: &Database, word: Id, limit: u32) -> Result<Vec<FormalLogDto>> {
    Ok(db
        .srs_read()
        .recent_logs(word, limit)?
        .into_iter()
        .map(Into::into)
        .collect())
}
pub fn eligible_new_words(
    db: &Database,
    book: Option<Id>,
    limit: u32,
    offset: u32,
) -> Result<Vec<Id>> {
    db.srs_read().eligible_new(book, limit, offset)
}
pub fn due_progress(
    db: &Database,
    now: Timestamp,
    calendar: &CalendarContext,
) -> Result<Vec<LearningProgress>> {
    db.srs_read().due(now, calendar.day_end_exclusive(now)?)
}
