pub mod db;

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
        phase: 2,
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

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() -> tauri::Result<()> {
    tauri::Builder::default()
        .setup(|app| {
            let directory = app.path().app_data_dir()?;
            let database = db::Database::open_app_data(&directory)?;
            app.manage(Mutex::new(database));
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![app_info, database_info])
        .run(tauri::generate_context!())
}
