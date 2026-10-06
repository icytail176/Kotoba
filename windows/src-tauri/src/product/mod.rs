//! Typed product commands. Storage errors never become ordinary user text.
pub(crate) mod files;
use crate::{
    db::{
        self, history::HistoryPage, models::*, product_mutations::*, product_reads::*,
        statistics::*,
    },
    settings::{AppSettings, SettingsStore},
    srs::models::DAY_MICROS,
    study::time::{self, SystemLocalTimeContextProvider},
};
use std::sync::{Mutex, MutexGuard};
fn lock<'a>(
    db: &'a tauri::State<'_, Mutex<db::Database>>,
) -> Result<MutexGuard<'a, db::Database>, String> {
    db.lock().map_err(|_| "本地词库暂时不可用，请重试。".into())
}
fn result<T>(value: db::Result<T>) -> Result<T, String> {
    value.map_err(|error| match error {
        db::DatabaseError::InvalidData("confirmation required") => "请先确认此操作。".into(),
        db::DatabaseError::InvalidData("duplicate expression and reading in book") => {
            "此词书已有相同表记和读音的单词。".into()
        }
        db::DatabaseError::InvalidData("built-in book cannot be deleted")
        | db::DatabaseError::InvalidData("built-in book metadata is protected") => {
            "内置词书不能修改或删除。".into()
        }
        _ => "本地操作未完成，数据已保留，请重试。".into(),
    })
}
fn now() -> Result<Timestamp, String> {
    time::now().map_err(|_| "无法读取系统时间。".into())
}
#[tauri::command]
pub(crate) fn product_words(
    query: WordQuery,
    database: tauri::State<'_, Mutex<db::Database>>,
) -> Result<ProductPage, String> {
    result(lock(&database)?.product_words(query))
}
#[tauri::command]
pub(crate) fn product_books(
    database: tauri::State<'_, Mutex<db::Database>>,
) -> Result<Vec<ProductBook>, String> {
    result(lock(&database)?.product_books())
}
#[tauri::command]
pub(crate) fn product_detail(
    id: Id,
    database: tauri::State<'_, Mutex<db::Database>>,
) -> Result<Option<ProductDetail>, String> {
    result(lock(&database)?.product_detail(id))
}
#[tauri::command]
pub(crate) fn product_filter_options(
    database: tauri::State<'_, Mutex<db::Database>>,
) -> Result<FilterOptions, String> {
    result(lock(&database)?.filter_options())
}
#[tauri::command]
pub(crate) fn product_history(
    id: Id,
    limit: u32,
    offset: u32,
    database: tauri::State<'_, Mutex<db::Database>>,
) -> Result<HistoryPage, String> {
    result(lock(&database)?.word_history(id, limit, offset))
}
#[tauri::command]
pub(crate) fn product_reset_word(
    id: Id,
    confirmed: bool,
    database: tauri::State<'_, Mutex<db::Database>>,
) -> Result<(), String> {
    result(lock(&database)?.reset_word(id, confirmed, now()?))
}
#[tauri::command]
pub(crate) fn product_reset_book(
    id: Id,
    confirmed: bool,
    database: tauri::State<'_, Mutex<db::Database>>,
) -> Result<(), String> {
    result(lock(&database)?.reset_book(id, confirmed, now()?))
}
#[tauri::command]
pub(crate) fn product_edit_word(
    edit: WordEdit,
    database: tauri::State<'_, Mutex<db::Database>>,
) -> Result<Id, String> {
    result(lock(&database)?.edit_word(edit, now()?))
}
#[tauri::command]
pub(crate) fn product_delete_word(
    id: Id,
    confirmed: bool,
    database: tauri::State<'_, Mutex<db::Database>>,
) -> Result<(), String> {
    result(lock(&database)?.delete_word(id, confirmed))
}
#[tauri::command]
pub(crate) fn product_edit_book(
    id: Option<Id>,
    name: String,
    description: String,
    database: tauri::State<'_, Mutex<db::Database>>,
) -> Result<Id, String> {
    result(lock(&database)?.edit_book(id, &name, &description, now()?))
}
#[tauri::command]
pub(crate) fn product_delete_book(
    id: Id,
    confirmed: bool,
    database: tauri::State<'_, Mutex<db::Database>>,
) -> Result<(), String> {
    result(lock(&database)?.delete_book(id, confirmed))
}
#[tauri::command]
pub(crate) fn product_random_example(
    book_id: Option<Id>,
    database: tauri::State<'_, Mutex<db::Database>>,
) -> Result<Option<ProductDetail>, String> {
    result(lock(&database)?.random_example(book_id))
}
#[tauri::command]
pub(crate) fn product_forecast(
    book_id: Option<Id>,
    database: tauri::State<'_, Mutex<db::Database>>,
) -> Result<Vec<ForecastDay>, String> {
    let now = now()?;
    let context = SystemLocalTimeContextProvider
        .context_between(
            Timestamp(now.0 - 3 * DAY_MICROS),
            Timestamp(now.0 + 10 * DAY_MICROS),
        )
        .map_err(|_| "无法读取本地时区。".to_string())?;
    result(lock(&database)?.forecast(now, &context.calendar, book_id))
}
#[tauri::command]
pub(crate) fn product_statistics(
    days: u32,
    database: tauri::State<'_, Mutex<db::Database>>,
) -> Result<Statistics, String> {
    let now = now()?;
    let db = lock(&database)?;
    let oldest = result(db.earliest_log())?.unwrap_or(now);
    let start = oldest
        .0
        .min(now.0 - 32 * DAY_MICROS)
        .checked_sub(3 * DAY_MICROS)
        .ok_or("统计日期超出范围。")?;
    let context = SystemLocalTimeContextProvider
        .context_between(Timestamp(start), Timestamp(now.0 + 3 * DAY_MICROS))
        .map_err(|_| "无法读取统计所需的本地时区。".to_string())?;
    result(db.statistics(now, &context.calendar, context.name, days))
}
#[tauri::command]
pub(crate) fn product_settings(
    settings: tauri::State<'_, Mutex<SettingsStore>>,
) -> Result<AppSettings, String> {
    Ok(settings
        .lock()
        .map_err(|_| "设置暂时不可用。".to_string())?
        .get())
}
#[tauri::command]
pub(crate) fn product_save_settings(
    value: AppSettings,
    settings: tauri::State<'_, Mutex<SettingsStore>>,
    database: tauri::State<'_, Mutex<db::Database>>,
) -> Result<AppSettings, String> {
    if let Some(id) = value.selected_book_id {
        if result(lock(&database)?.fetch_book(id))?.is_none() {
            return Err("所选词书已不存在，请重新选择。".into());
        }
    }
    settings
        .lock()
        .map_err(|_| "设置暂时不可用。".to_string())?
        .save(value)
}

#[tauri::command]
pub(crate) fn product_editor_preview(
    expression: String,
    reading: String,
    part_of_speech: String,
) -> crate::lexical::preview::EditorPreview {
    crate::lexical::preview::editor(&expression, &reading, &part_of_speech)
}
