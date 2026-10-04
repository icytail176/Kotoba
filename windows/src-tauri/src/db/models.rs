use rusqlite::types::{FromSql, FromSqlError, FromSqlResult, ToSql, ToSqlOutput, ValueRef};
use std::fmt;

/// An externally supplied entity UUID, not a built-in lexical identity generator.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Id(uuid::Uuid);

impl Id {
    pub fn parse(value: &str) -> Result<Self, uuid::Error> {
        uuid::Uuid::parse_str(value).map(Self)
    }
}
impl fmt::Display for Id {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0.hyphenated())
    }
}
impl ToSql for Id {
    fn to_sql(&self) -> rusqlite::Result<ToSqlOutput<'_>> {
        Ok(self.to_string().into())
    }
}
impl FromSql for Id {
    fn column_result(value: ValueRef<'_>) -> FromSqlResult<Self> {
        let text = value.as_str()?;
        let id = Self::parse(text).map_err(|e| FromSqlError::Other(Box::new(e)))?;
        if id.to_string() != text {
            return Err(FromSqlError::InvalidType);
        }
        Ok(id)
    }
}

/// Signed UTC microseconds since 1970-01-01T00:00:00Z. Never locale text.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Timestamp(pub i64);
impl ToSql for Timestamp {
    fn to_sql(&self) -> rusqlite::Result<ToSqlOutput<'_>> {
        self.0.to_sql()
    }
}
impl FromSql for Timestamp {
    fn column_result(value: ValueRef<'_>) -> FromSqlResult<Self> {
        i64::column_result(value).map(Self)
    }
}

macro_rules! text_enum {
    ($name:ident { $($variant:ident => $raw:literal),+ $(,)? }) => {
        #[derive(Debug, Clone, Copy, PartialEq, Eq)]
        pub enum $name { $($variant),+ }
        impl $name {
            pub fn as_str(self) -> &'static str { match self { $(Self::$variant => $raw),+ } }
            pub fn parse(value: &str) -> Option<Self> { match value { $($raw => Some(Self::$variant)),+, _ => None } }
        }
        impl ToSql for $name {
            fn to_sql(&self) -> rusqlite::Result<ToSqlOutput<'_>> { Ok(self.as_str().into()) }
        }
        impl FromSql for $name {
            fn column_result(value: ValueRef<'_>) -> FromSqlResult<Self> {
                Self::parse(value.as_str()?).ok_or(FromSqlError::InvalidType)
            }
        }
    };
}
text_enum!(LearningState { New => "new", Learning => "learning", Relearning => "relearning", Review => "review", Suspended => "suspended" });
text_enum!(ReviewRating { Again => "again", Hard => "hard", Good => "good", Easy => "easy" });
text_enum!(ReviewErrorType { Meaning => "meaning", Reading => "reading", Spelling => "spelling", ExpressionDirection => "expressionDirection", ReadingDirection => "readingDirection" });

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WordBook {
    pub id: Id,
    pub name: String,
    pub book_description: String,
    pub created_at: Timestamp,
    pub updated_at: Timestamp,
    pub is_built_in: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VocabularyWord {
    pub id: Id,
    pub japanese: String,
    pub kana: String,
    pub chinese_meaning: String,
    pub part_of_speech: String,
    pub jlpt_level: String,
    pub example_japanese: String,
    pub example_chinese: String,
    pub tags: Vec<String>,
    pub created_at: Timestamp,
    pub updated_at: Timestamp,
    pub is_archived: bool,
    pub is_favorite: bool,
    pub loanword_source_term: Option<String>,
    pub loanword_source_language_code: Option<String>,
    pub loanword_is_wasei: bool,
    pub loanword_is_partial: bool,
    pub word_book_id: Option<Id>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LearningProgress {
    pub id: Id,
    pub word_id: Id,
    pub state: LearningState,
    pub due_at: Timestamp,
    pub interval_days: i64,
    pub review_count: i64,
    pub lapse_count: i64,
    pub last_reviewed_at: Option<Timestamp>,
    pub created_at: Timestamp,
    pub updated_at: Timestamp,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReviewLog {
    pub id: Id,
    pub word_id: Id,
    pub reviewed_at: Timestamp,
    pub rating: ReviewRating,
    pub previous_state: LearningState,
    pub next_state: LearningState,
    pub previous_interval_days: i64,
    pub next_interval_days: i64,
    pub scheduled_due_at: Timestamp,
    pub error_types: Vec<ReviewErrorType>,
    pub typed_answer: Option<String>,
    pub expected_answer: Option<String>,
    pub question_direction_raw_value: Option<String>,
    pub reading_wrong_count: i64,
    pub spelling_wrong_count: i64,
    pub repeated_wrong_count: i64,
}
