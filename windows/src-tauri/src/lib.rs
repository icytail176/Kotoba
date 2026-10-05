pub mod db;
pub mod vocabulary;

use std::sync::Mutex;
use tauri::Manager;

#[derive(serde::Serialize)]
struct AppInfo {
    name: &'static str,
    platform: &'static str,
    phase: u8,
}

#[tauri::command]
fn app_info() -> AppInfo {
    AppInfo {
        name: "Kotoba",
        platform: std::env::consts::OS,
        phase: 3,
    }
}

#[tauri::command]
fn database_info(
    database: tauri::State<'_, Mutex<db::Database>>,
) -> Result<db::DatabaseInfo, String> {
    let database = database
        .lock()
        .map_err(|_| "Database service lock failed".to_string())?;
    database.info().map_err(|error| error.to_string())
}

#[tauri::command]
fn list_builtin_word_books(
    database: tauri::State<'_, Mutex<db::Database>>,
) -> Result<Vec<db::BookSummary>, String> {
    database
        .lock()
        .map_err(|_| "Database service lock failed".to_string())?
        .list_builtin_word_books()
        .map_err(|e| e.to_string())
}
#[tauri::command]
fn get_word_book_summary(
    id: String,
    database: tauri::State<'_, Mutex<db::Database>>,
) -> Result<Option<db::BookSummary>, String> {
    let id = db::models::Id::parse(&id).map_err(|e| e.to_string())?;
    database
        .lock()
        .map_err(|_| "Database service lock failed".to_string())?
        .get_word_book_summary(id)
        .map_err(|e| e.to_string())
}
#[tauri::command]
fn list_words(
    book_id: String,
    limit: u32,
    offset: u32,
    database: tauri::State<'_, Mutex<db::Database>>,
) -> Result<db::WordPage, String> {
    let id = db::models::Id::parse(&book_id).map_err(|e| e.to_string())?;
    database
        .lock()
        .map_err(|_| "Database service lock failed".to_string())?
        .list_words(id, limit, offset)
        .map_err(|e| e.to_string())
}
#[tauri::command]
fn get_word(
    id: String,
    database: tauri::State<'_, Mutex<db::Database>>,
) -> Result<Option<db::models::VocabularyWord>, String> {
    let id = db::models::Id::parse(&id).map_err(|e| e.to_string())?;
    database
        .lock()
        .map_err(|_| "Database service lock failed".to_string())?
        .fetch_word(id)
        .map_err(|e| e.to_string())
}
#[tauri::command]
fn search_words(
    query: String,
    limit: u32,
    offset: u32,
    database: tauri::State<'_, Mutex<db::Database>>,
) -> Result<db::WordPage, String> {
    database
        .lock()
        .map_err(|_| "Database service lock failed".to_string())?
        .search_words(&query, limit, offset)
        .map_err(|e| e.to_string())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() -> tauri::Result<()> {
    tauri::Builder::default()
        .setup(|app| {
            let directory = app.path().app_data_dir()?;
            let mut database = db::Database::open_app_data(&directory)?;
            let manifest = vocabulary::Manifest::embedded()?;
            let micros = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map_err(|_| db::DatabaseError::InvalidData("system clock before Unix epoch"))?
                .as_micros();
            let now = i64::try_from(micros)
                .map_err(|_| db::DatabaseError::InvalidData("system clock out of range"))?;
            database.import_builtin(&manifest, db::models::Timestamp(now))?;
            app.manage(Mutex::new(database));
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            app_info,
            database_info,
            list_builtin_word_books,
            get_word_book_summary,
            list_words,
            get_word,
            search_words
        ])
        .run(tauri::generate_context!())
}
