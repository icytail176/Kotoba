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
        phase: 4,
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

// Product reads use dedicated DTOs; legacy database diagnostics remain separate.
#[tauri::command]
fn browse_books(
    database: tauri::State<'_, Mutex<db::Database>>,
) -> Result<Vec<db::WordBookSummary>, String> {
    database
        .lock()
        .map_err(|_| "Read service unavailable".to_string())?
        .browse_books()
        .map_err(|e| e.to_string())
}
#[tauri::command]
fn browse_words(
    book_id: Option<String>,
    limit: u32,
    offset: u32,
    database: tauri::State<'_, Mutex<db::Database>>,
) -> Result<db::PagedWords, String> {
    let book = book_id
        .map(|id| db::models::Id::parse(&id))
        .transpose()
        .map_err(|e| e.to_string())?;
    database
        .lock()
        .map_err(|_| "Read service unavailable".to_string())?
        .browse_words(book, limit, offset)
        .map_err(|e| e.to_string())
}
#[tauri::command]
fn browse_search(
    query: String,
    limit: u32,
    offset: u32,
    database: tauri::State<'_, Mutex<db::Database>>,
) -> Result<db::PagedWords, String> {
    database
        .lock()
        .map_err(|_| "Read service unavailable".to_string())?
        .browse_search(&query, limit, offset)
        .map_err(|e| e.to_string())
}
#[tauri::command]
fn word_detail(
    id: String,
    database: tauri::State<'_, Mutex<db::Database>>,
) -> Result<Option<db::WordDetail>, String> {
    let id = db::models::Id::parse(&id).map_err(|e| e.to_string())?;
    database
        .lock()
        .map_err(|_| "Read service unavailable".to_string())?
        .word_detail(id)
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
            browse_books,
            browse_words,
            browse_search,
            word_detail
        ])
        .run(tauri::generate_context!())
}
