// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    // CI runs the actual release executable from an empty directory. This
    // read-only probe neither starts Tauri nor opens a production database.
    if std::env::args().any(|arg| arg == "--verify-embedded-manifest") {
        match kotoba_windows_lib::vocabulary::Manifest::embedded() {
            Ok(manifest) => {
                println!(
                    "{}",
                    serde_json::json!({
                        "manifestVersion": manifest.manifest_version,
                        "entryCount": manifest.entry_count,
                        "books": manifest.books.iter().map(|book| (&book.canonical_key,book.entry_count)).collect::<Vec<_>>()
                    })
                );
                return;
            }
            Err(error) => {
                eprintln!("Embedded manifest verification failed: {error}");
                std::process::exit(1);
            }
        }
    }
    if let Err(error) = kotoba_windows_lib::run() {
        eprintln!("Failed to run Kotoba: {error}");
        std::process::exit(1);
    }
}
