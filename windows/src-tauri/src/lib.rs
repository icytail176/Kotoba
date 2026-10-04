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
        phase: 0,
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() -> tauri::Result<()> {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![app_info])
        .run(tauri::generate_context!())
}
