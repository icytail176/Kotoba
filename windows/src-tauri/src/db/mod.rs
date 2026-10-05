mod builtin;
mod migrations;
pub mod models;
mod reads;
mod repository;
pub use builtin::ImportResult;
pub use reads::{BookSummary, WordPage};

use rusqlite::Connection;
use std::{error::Error, fmt, path::Path, time::Duration};

pub type Result<T> = std::result::Result<T, DatabaseError>;

#[derive(Debug)]
pub enum DatabaseError {
    Sqlite(rusqlite::Error),
    Io(std::io::Error),
    Json(serde_json::Error),
    UnsupportedSchema(i64),
    InvalidData(&'static str),
    Manifest(String),
    Migration {
        version: u32,
        source: rusqlite::Error,
    },
}
impl fmt::Display for DatabaseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Sqlite(e) => write!(f, "SQLite operation failed: {e}"),
            Self::Io(e) => write!(f, "Database directory operation failed: {e}"),
            Self::Json(e) => write!(f, "Database JSON encoding failed: {e}"),
            Self::UnsupportedSchema(v) => {
                write!(f, "Unsupported database schema {v}; database was not reset")
            }
            Self::Manifest(message) => write!(f, "Invalid canonical manifest: {message}"),
            Self::InvalidData(message) => write!(f, "Invalid database data: {message}"),
            Self::Migration { version, source } => {
                write!(f, "Migration to schema {version} failed: {source}")
            }
        }
    }
}
impl Error for DatabaseError {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        match self {
            Self::Sqlite(e) | Self::Migration { source: e, .. } => Some(e),
            Self::Io(e) => Some(e),
            Self::Json(e) => Some(e),
            _ => None,
        }
    }
}
impl From<rusqlite::Error> for DatabaseError {
    fn from(e: rusqlite::Error) -> Self {
        Self::Sqlite(e)
    }
}
impl From<std::io::Error> for DatabaseError {
    fn from(e: std::io::Error) -> Self {
        Self::Io(e)
    }
}
impl From<serde_json::Error> for DatabaseError {
    fn from(e: serde_json::Error) -> Self {
        Self::Json(e)
    }
}

#[derive(Debug, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TableCounts {
    pub word_books: i64,
    pub vocabulary_words: i64,
    pub learning_progress: i64,
    pub review_logs: i64,
}
#[derive(Debug, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DatabaseInfo {
    pub schema_version: u32,
    /// Display-safe relative description, never a user-specific absolute path.
    pub location: &'static str,
    pub table_counts: TableCounts,
    pub manifest_version: Option<u32>,
}

pub struct Database {
    pub(crate) connection: Connection,
}
impl Database {
    /// Production caller resolves this directory with Tauri's app_data_dir().
    pub fn open_app_data(directory: &Path) -> Result<Self> {
        std::fs::create_dir_all(directory)?;
        Self::open(&directory.join("kotoba.sqlite3"))
    }
    /// Explicit path for integration tests/tools. Production never uses the cwd.
    pub fn open(path: &Path) -> Result<Self> {
        Self::configure(Connection::open(path)?)
    }
    pub fn in_memory() -> Result<Self> {
        Self::configure(Connection::open_in_memory()?)
    }
    fn configure(mut connection: Connection) -> Result<Self> {
        connection.busy_timeout(Duration::from_secs(5))?;
        connection.pragma_update(None, "foreign_keys", "ON")?;
        migrations::apply(&mut connection)?;
        Ok(Self { connection })
    }
    pub fn info(&self) -> Result<DatabaseInfo> {
        Ok(DatabaseInfo {
            schema_version: self
                .connection
                .pragma_query_value(None, "user_version", |row| row.get(0))?,
            location: "app-data/kotoba.sqlite3",
            manifest_version: self.manifest_version()?,
            table_counts: TableCounts {
                word_books: self.connection.query_row(
                    "SELECT count(*) FROM word_books",
                    [],
                    |r| r.get(0),
                )?,
                vocabulary_words: self.connection.query_row(
                    "SELECT count(*) FROM vocabulary_words",
                    [],
                    |r| r.get(0),
                )?,
                learning_progress: self.connection.query_row(
                    "SELECT count(*) FROM learning_progress",
                    [],
                    |r| r.get(0),
                )?,
                review_logs: self.connection.query_row(
                    "SELECT count(*) FROM review_logs",
                    [],
                    |r| r.get(0),
                )?,
            },
        })
    }
}

#[cfg(test)]
mod tests;

#[cfg(test)]
mod builtin_tests;
