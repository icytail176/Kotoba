pub mod db;
pub mod lexical;
mod product;
pub mod settings;
pub mod srs;
pub mod study;
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
        phase: 7,
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
        .plugin(tauri_plugin_dialog::init())
        .setup(|app| {
            let directory = app.path().app_data_dir()?;
            // Explicit isolated data for development/manual session audits only.
            // Release builds always use the normal Tauri app-data directory.
            #[cfg(debug_assertions)]
            let directory = match std::env::var_os("KOTOBA_TEST_APP_DATA") {
                Some(path) => {
                    let path = std::path::PathBuf::from(path);
                    if !path.is_absolute() {
                        return Err("test app-data path must be absolute".into());
                    }
                    path
                }
                None => directory,
            };
            let mut database = db::Database::open_app_data(&directory)?;
            let manifest = vocabulary::Manifest::embedded()?;
            let micros = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map_err(|_| db::DatabaseError::InvalidData("system clock before Unix epoch"))?
                .as_micros();
            let now = i64::try_from(micros)
                .map_err(|_| db::DatabaseError::InvalidData("system clock out of range"))?;
            database.import_builtin(&manifest, db::models::Timestamp(now))?;
            app.manage(Mutex::new(
                settings::SettingsStore::open(&directory).map_err(std::io::Error::other)?,
            ));
            app.manage(Mutex::new(product::files::Staging::default()));
            app.manage(Mutex::new(database));
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            product::product_editor_preview,
            product::product_words,
            product::product_books,
            product::product_detail,
            product::product_filter_options,
            product::product_history,
            product::product_reset_word,
            product::product_reset_book,
            product::product_edit_word,
            product::product_delete_word,
            product::product_edit_book,
            product::product_delete_book,
            product::product_forecast,
            product::product_statistics,
            product::product_random_example,
            product::product_settings,
            product::product_save_settings,
            product::files::product_export_quality,
            product::files::product_pick_import,
            product::files::product_confirm_import,
            product::files::product_cancel_import,
            product::files::product_export_file,
            app_info,
            database_info,
            browse_books,
            browse_words,
            browse_search,
            word_detail,
            study::ipc::study_availability,
            study::ipc::study_start,
            study::ipc::study_formal,
            study::ipc::study_reinforcement_mastered,
            study::ipc::study_favorite,
            study::ipc::study_enrich
        ])
        .run(tauri::generate_context!())
}
