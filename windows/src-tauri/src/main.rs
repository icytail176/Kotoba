// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    if let Err(error) = kotoba_windows_lib::run() {
        eprintln!("Failed to run Kotoba: {error}");
        std::process::exit(1);
    }
}
