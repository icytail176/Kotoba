use super::{
    models::*,
    queue::{self, QueuePolicy},
    service,
    time::{self, LocalTimeContextProvider, SystemLocalTimeContextProvider},
};
use crate::db::{models::*, Database};
use std::sync::{Mutex, MutexGuard};
fn lock<'a>(database: &'a tauri::State<'_, Mutex<Database>>) -> Result<MutexGuard<'a, Database>> {
    database.lock().map_err(|_| StudyError {
        code: "save",
        message: "本地学习服务不可用，请重试。",
    })
}
#[tauri::command]
pub(crate) fn study_availability(
    book_id: Id,
    database: tauri::State<'_, Mutex<Database>>,
) -> Result<Availability> {
    let now = time::now()?;
    let context = SystemLocalTimeContextProvider.context(now)?;
    queue::availability(
        &*lock(&database)?,
        book_id,
        now,
        &context.calendar,
        context.name,
    )
}
#[tauri::command]
pub(crate) fn study_start(
    book_id: Id,
    mode: SessionMode,
    new_limit: u32,
    settings: tauri::State<'_, Mutex<crate::settings::SettingsStore>>,
    review_limit: u32,
    database: tauri::State<'_, Mutex<Database>>,
) -> Result<SessionStart> {
    let now = time::now()?;
    let context = SystemLocalTimeContextProvider.context(now)?;
    queue::start(
        &*lock(&database)?,
        book_id,
        mode,
        now,
        &context.calendar,
        QueuePolicy {
            new_limit,
            review_limit,
            randomizes: settings
                .lock()
                .map_err(|_| StudyError {
                    code: "save",
                    message: "本地设置暂时不可用。",
                })?
                .get()
                .randomizes_study_order,
        },
        context.name,
    )
}
#[tauri::command]
pub(crate) fn study_formal(
    request: FormalRequest,
    database: tauri::State<'_, Mutex<Database>>,
) -> Result<FormalCommit> {
    let context = SystemLocalTimeContextProvider.context(request.now)?;
    service::formal(&mut *lock(&database)?, request, &context.calendar)
}
#[tauri::command]
pub(crate) fn study_reinforcement_mastered(
    word_id: Id,
    expected_progress: LearningProgress,
    now: Timestamp,
    database: tauri::State<'_, Mutex<Database>>,
) -> Result<LearningProgress> {
    service::reinforcement_mastered(&mut *lock(&database)?, word_id, expected_progress, now)
}
#[tauri::command]
pub(crate) fn study_favorite(
    word_id: Id,
    expected: bool,
    database: tauri::State<'_, Mutex<Database>>,
) -> Result<bool> {
    service::favorite(&mut *lock(&database)?, word_id, expected, time::now()?)
}
#[tauri::command]
pub(crate) fn study_enrich(
    entries: Vec<Enrichment>,
    database: tauri::State<'_, Mutex<Database>>,
) -> Result<()> {
    service::enrich(&mut *lock(&database)?, entries)
}
