use crate::db::{models::*, DatabaseError};
use std::{error::Error, fmt};

pub const MAX_INTERVAL_DAYS: i64 = 60;
pub const MINUTE_MICROS: i64 = 60_000_000;
pub const DAY_MICROS: i64 = 86_400_000_000;
pub type Result<T> = std::result::Result<T, SrsError>;

#[derive(Debug)]
pub enum SrsError {
    MissingWord,
    ArchivedWord,
    SuspendedWord,
    StaleProgress,
    InvalidState,
    InvalidRating,
    InvalidProgress,
    InvalidLimit,
    CounterOverflow,
    DateOverflow,
    InvalidCalendar,
    CalendarCoverage,
    Database(DatabaseError),
}
impl fmt::Display for SrsError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "SRS operation failed: {self:?}")
    }
}
impl Error for SrsError {}
impl From<DatabaseError> for SrsError {
    fn from(value: DatabaseError) -> Self {
        Self::Database(value)
    }
}
impl From<rusqlite::Error> for SrsError {
    fn from(value: rusqlite::Error) -> Self {
        Self::Database(value.into())
    }
}

/// Only formal card evaluation enters this API. No reinforcement/spelling variant.
#[derive(Debug, Clone, Copy)]
pub struct FormalRating(pub ReviewRating);
impl FormalRating {
    pub fn parse(raw: &str) -> Result<Self> {
        ReviewRating::parse(raw)
            .map(Self)
            .ok_or(SrsError::InvalidRating)
    }
}
pub fn parse_state(raw: &str) -> Result<LearningState> {
    LearningState::parse(raw).ok_or(SrsError::InvalidState)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Schedule {
    pub state: LearningState,
    pub interval_days: i64,
    pub due_at: Timestamp,
    pub review_count: i64,
    pub lapse_count: i64,
    pub did_lapse: bool,
    pub automatic_mastery: bool,
}

/// Pure scheduler input, independent of row IDs, persistence and UI state.
#[derive(Debug, Clone, Copy)]
pub struct ProgressSnapshot {
    pub state: LearningState,
    pub interval_days: i64,
    pub review_count: i64,
    pub lapse_count: i64,
}
impl From<&LearningProgress> for ProgressSnapshot {
    fn from(progress: &LearningProgress) -> Self {
        Self {
            state: progress.state,
            interval_days: progress.interval_days,
            review_count: progress.review_count,
            lapse_count: progress.lapse_count,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub enum LearningStatusPresentation {
    Unlearned,
    Reviewing,
    Mastered,
}
impl LearningStatusPresentation {
    pub fn from_state(state: Option<LearningState>) -> Self {
        match state {
            None | Some(LearningState::New) => Self::Unlearned,
            Some(LearningState::Suspended) => Self::Mastered,
            _ => Self::Reviewing,
        }
    }
}

#[derive(Debug, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FormalLogDto {
    pub id: Id,
    pub reviewed_at: Timestamp,
    pub rating: ReviewRating,
    pub previous_state: LearningState,
    pub next_state: LearningState,
    pub previous_interval_days: i64,
    pub next_interval_days: i64,
    pub scheduled_due_at: Timestamp,
}
impl From<ReviewLog> for FormalLogDto {
    fn from(log: ReviewLog) -> Self {
        Self {
            id: log.id,
            reviewed_at: log.reviewed_at,
            rating: log.rating,
            previous_state: log.previous_state,
            next_state: log.next_state,
            previous_interval_days: log.previous_interval_days,
            next_interval_days: log.next_interval_days,
            scheduled_due_at: log.scheduled_due_at,
        }
    }
}
