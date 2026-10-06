use crate::db::{models::*, WordDetail};
use crate::srs::models::SrsError;

#[derive(Debug, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StudyError {
    pub code: &'static str,
    pub message: &'static str,
}
pub type Result<T> = std::result::Result<T, StudyError>;
impl std::fmt::Display for StudyError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}: {}", self.code, self.message)
    }
}
impl std::error::Error for StudyError {}
impl StudyError {
    pub fn invalid() -> Self {
        Self {
            code: "invalid",
            message: "学习数据无效，请重新开始本组学习。",
        }
    }
    pub fn timezone() -> Self {
        Self {
            code: "timezone",
            message: "无法读取当前系统时区，请检查系统时区设置后重试。",
        }
    }
}
impl From<SrsError> for StudyError {
    fn from(e: SrsError) -> Self {
        match e {
            SrsError::StaleProgress
            | SrsError::ArchivedWord
            | SrsError::SuspendedWord
            | SrsError::MissingWord => Self {
                code: "stale",
                message: "学习状态已发生变化，请重新开始本组学习。",
            },
            SrsError::InvalidCalendar | SrsError::CalendarCoverage => Self::timezone(),
            _ => Self {
                code: "save",
                message: "保存失败，请重试。",
            },
        }
    }
}
impl From<crate::db::DatabaseError> for StudyError {
    fn from(_: crate::db::DatabaseError) -> Self {
        Self {
            code: "save",
            message: "保存失败，请重试。",
        }
    }
}
impl From<rusqlite::Error> for StudyError {
    fn from(e: rusqlite::Error) -> Self {
        crate::db::DatabaseError::from(e).into()
    }
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Deserialize, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub enum SessionMode {
    Mixed,
    NewWordsOnly,
    DueReviewsOnly,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub enum CardKind {
    NewWord,
    DueReview,
}
#[derive(Debug, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StudyCard {
    pub word: WordDetail,
    pub kind: CardKind,
    pub expected_progress: Option<LearningProgress>,
    pub is_favorite: bool,
}
#[derive(Debug, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionStart {
    pub cards: Vec<StudyCard>,
    pub timezone: String,
}
#[derive(Debug, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Availability {
    pub new_count: u32,
    pub due_count: u32,
    pub total_count: u32,
    pub reviewing_count: u32,
    pub mastered_count: u32,
    pub timezone: String,
}
#[derive(Debug, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FormalCommit {
    pub progress: LearningProgress,
    pub log_id: Id,
    pub automatic_mastery: bool,
    pub did_lapse: bool,
}
#[derive(Debug, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct FormalRequest {
    pub word_id: Id,
    pub expected_progress: Option<LearningProgress>,
    pub rating: ReviewRating,
    pub now: Timestamp,
}
#[derive(Debug, Clone, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Enrichment {
    pub word_id: Id,
    pub log_id: Id,
    pub typed_answer: Option<String>,
    pub expected_answer: Option<String>,
    pub question_direction_raw_value: Option<String>,
    pub reading_wrong_count: i64,
    pub spelling_wrong_count: i64,
}
