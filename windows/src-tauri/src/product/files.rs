//! Native dialog access and opaque staged import plans. Frontend never supplies paths.
use super::{lock, now, result};
use crate::{
    db::{self, backup::*, csv::*, models::*},
    settings::atomic_write,
};
use serde::{Deserialize, Serialize};
use std::{path::Path, sync::Mutex};
use tauri::Manager;
use tauri_plugin_dialog::DialogExt;
const MAX_FILE: u64 = 64 * 1024 * 1024;
#[derive(Clone, Copy, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) enum FileKind {
    Csv,
    Backup,
}
impl FileKind {
    fn extension(self) -> &'static str {
        match self {
            Self::Csv => "csv",
            Self::Backup => "json",
        }
    }
    fn title(self) -> &'static str {
        match self {
            Self::Csv => "CSV 词库",
            Self::Backup => "Windows 本地备份",
        }
    }
}
enum Plan {
    Csv(CsvPlan, ImportTarget, db::quality::QualityReport),
    Backup(Backup),
}
#[derive(Default)]
pub(crate) struct Staging {
    plan: Option<(Id, Plan)>,
}
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct Preview {
    token: Id,
    kind: &'static str,
    file_name: String,
    valid_rows: usize,
    duplicate_rows: u32,
    errors: Vec<CsvError>,
    error_count: usize,
    sample: Vec<CsvRow>,
    books: usize,
    words: usize,
    progress: usize,
    logs: usize,
    quality: Option<db::quality::QualityReport>,
}
fn safe_file(path: &Path, extension: &str) -> Result<(), String> {
    if path
        .extension()
        .and_then(|e| e.to_str())
        .is_none_or(|e| !e.eq_ignore_ascii_case(extension))
    {
        return Err(format!("请选择 .{extension} 文件。"));
    }
    Ok(())
}
fn file_bytes(path: &Path) -> Result<Vec<u8>, String> {
    let metadata = std::fs::metadata(path).map_err(|_| "文件无法读取，请检查权限。".to_string())?;
    if !metadata.is_file() || metadata.len() > MAX_FILE {
        return Err("文件必须小于 64 MB。".into());
    }
    let bytes = std::fs::read(path).map_err(|_| "文件无法读取。".to_string())?;
    if bytes.len() as u64 > MAX_FILE {
        return Err("文件超过大小限制。".into());
    }
    Ok(bytes)
}
#[tauri::command]
pub(crate) async fn product_pick_import(
    app: tauri::AppHandle,
    kind: FileKind,
    target: Option<ImportTarget>,
) -> Result<Option<Preview>, String> {
    app.state::<Mutex<Staging>>()
        .lock()
        .map_err(|_| "导入服务暂时不可用。".to_string())?
        .plan = None;
    let app_copy = app.clone();
    let chosen = tauri::async_runtime::spawn_blocking(move || {
        app_copy
            .dialog()
            .file()
            .set_title(kind.title())
            .add_filter(kind.title(), &[kind.extension()])
            .blocking_pick_file()
    })
    .await
    .map_err(|_| "文件选择未完成。".to_string())?;
    let Some(chosen) = chosen else {
        return Ok(None);
    };
    let path = chosen
        .into_path()
        .map_err(|_| "请选择本地文件。".to_string())?;
    safe_file(&path, kind.extension())?;
    let bytes = tauri::async_runtime::spawn_blocking(move || file_bytes(&path).map(|b| (path, b)))
        .await
        .map_err(|_| "文件读取未完成。".to_string())??;
    let (path, bytes) = bytes;
    let token = Id::new_local();
    let file_name = path
        .file_name()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_default();
    let (preview, plan) = match kind {
        FileKind::Csv => {
            let target = target.ok_or("请先选择导入词书。")?;
            if target.book_id.is_some() == target.new_book_name.is_some() {
                return Err("请选择现有词书或填写新词书名称。".into());
            }
            let text =
                String::from_utf8(bytes).map_err(|_| "CSV 必须使用 UTF-8 编码。".to_string())?;
            let plan = parse(&text);
            let duplicate_rows = result(
                lock(&app.state::<Mutex<db::Database>>())?.csv_duplicate_count(&plan, &target),
            )?;
            let quality = result(
                lock(&app.state::<Mutex<db::Database>>())?.csv_quality(&plan, target.book_id),
            )?;
            let mut preview_quality = quality.clone();
            preview_quality.issues.truncate(100);
            (
                Preview {
                    token,
                    kind: "csv",
                    file_name,
                    valid_rows: plan.rows.len(),
                    duplicate_rows,
                    errors: plan.errors.iter().take(100).cloned().collect(),
                    error_count: plan.errors.len(),
                    sample: plan.rows.iter().take(20).cloned().collect(),
                    books: 0,
                    words: 0,
                    progress: 0,
                    logs: 0,
                    quality: Some(preview_quality),
                },
                Plan::Csv(plan, target, quality),
            )
        }
        FileKind::Backup => {
            let backup = Backup::parse(&bytes).map_err(|_| {
                "备份校验失败。仅支持 Kotoba Windows 本地格式；Mac V3 文件不可恢复。".to_string()
            })?;
            (
                Preview {
                    token,
                    kind: "backup",
                    file_name,
                    valid_rows: 0,
                    duplicate_rows: 0,
                    errors: vec![],
                    error_count: 0,
                    sample: vec![],
                    books: backup.books.len(),
                    words: backup.words.len(),
                    progress: backup.progress.len(),
                    logs: backup.logs.len(),
                    quality: None,
                },
                Plan::Backup(backup),
            )
        }
    };
    app.state::<Mutex<Staging>>()
        .lock()
        .map_err(|_| "导入服务暂时不可用。".to_string())?
        .plan = Some((token, plan));
    Ok(Some(preview))
}
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct FileSummary {
    pub csv: Option<ImportSummary>,
    pub backup: Option<RestoreSummary>,
}
#[tauri::command]
pub(crate) fn product_confirm_import(
    token: Id,
    confirmed: bool,
    duplicate_policy: Option<DuplicatePolicy>,
    restore_policy: Option<RestorePolicy>,
    staging: tauri::State<'_, Mutex<Staging>>,
    database: tauri::State<'_, Mutex<db::Database>>,
) -> Result<FileSummary, String> {
    if !confirmed {
        return Err("请先确认导入或恢复。".into());
    }
    let mut staged = staging
        .lock()
        .map_err(|_| "导入服务暂时不可用。".to_string())?;
    let Some((id, plan)) = &staged.plan else {
        return Err("预览已失效，请重新选择文件。".into());
    };
    if *id != token {
        return Err("预览已失效，请重新选择文件。".into());
    }
    let db = lock(&database)?;
    let summary = match plan {
        Plan::Csv(plan, target, _) => FileSummary {
            csv: Some(result(db.csv_import(
                plan,
                target.clone(),
                duplicate_policy.ok_or("请选择重复单词处理方式。")?,
                true,
                now()?,
            ))?),
            backup: None,
        },
        Plan::Backup(plan) => FileSummary {
            csv: None,
            backup: Some(result(db.backup_restore(
                plan,
                restore_policy.ok_or("请选择恢复方式。")?,
                true,
            ))?),
        },
    };
    staged.plan = None;
    Ok(summary)
}
#[tauri::command]
pub(crate) fn product_cancel_import(
    staging: tauri::State<'_, Mutex<Staging>>,
) -> Result<(), String> {
    staging
        .lock()
        .map_err(|_| "导入服务暂时不可用。".to_string())?
        .plan = None;
    Ok(())
}
#[tauri::command]
pub(crate) async fn product_export_file(
    app: tauri::AppHandle,
    kind: FileKind,
    book_id: Option<Id>,
) -> Result<Option<String>, String> {
    let data = {
        let state = app.state::<Mutex<db::Database>>();
        let db = lock(&state)?;
        match kind {
            FileKind::Csv => {
                result(db.csv_export(book_id.ok_or("请选择导出词书。")?))?.into_bytes()
            }
            FileKind::Backup => serde_json::to_vec_pretty(&result(db.backup_export(now()?))?)
                .map_err(|_| "备份生成失败。".to_string())?,
        }
    };
    let app_copy = app.clone();
    let chosen = tauri::async_runtime::spawn_blocking(move || {
        app_copy
            .dialog()
            .file()
            .set_title(kind.title())
            .add_filter(kind.title(), &[kind.extension()])
            .set_file_name(format!("Kotoba.{}", kind.extension()))
            .blocking_save_file()
    })
    .await
    .map_err(|_| "文件选择未完成。".to_string())?;
    let Some(chosen) = chosen else {
        return Ok(None);
    };
    let path = chosen
        .into_path()
        .map_err(|_| "请选择本地保存位置。".to_string())?;
    safe_file(&path, kind.extension())?;
    let name = path
        .file_name()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_default();
    tauri::async_runtime::spawn_blocking(move || {
        atomic_write(&path, &data)
            .map_err(|_| "文件保存失败，原文件已保留，请检查权限。".to_string())
    })
    .await
    .map_err(|_| "文件保存未完成。".to_string())??;
    Ok(Some(name))
}

#[tauri::command]
pub(crate) async fn product_export_quality(
    app: tauri::AppHandle,
    token: Id,
) -> Result<Option<String>, String> {
    let report = {
        let state = app.state::<Mutex<Staging>>();
        let stage = state
            .lock()
            .map_err(|_| "质量报告暂时不可用。".to_string())?;
        match &stage.plan {
            Some((id, Plan::Csv(_, _, quality))) if *id == token => quality.csv().into_bytes(),
            _ => return Err("预览已失效，请重新选择文件。".into()),
        }
    };
    let copy = app.clone();
    let path = tauri::async_runtime::spawn_blocking(move || {
        copy.dialog()
            .file()
            .set_title("导出质量报告")
            .add_filter("CSV", &["csv"])
            .set_file_name("Kotoba-quality.csv")
            .blocking_save_file()
    })
    .await
    .map_err(|_| "文件选择未完成。".to_string())?;
    let Some(path) = path else { return Ok(None) };
    let path = path
        .into_path()
        .map_err(|_| "请选择本地文件。".to_string())?;
    safe_file(&path, "csv")?;
    let name = path
        .file_name()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_default();
    tauri::async_runtime::spawn_blocking(move || {
        atomic_write(&path, &report).map_err(|_| "质量报告保存失败。".to_string())
    })
    .await
    .map_err(|_| "文件保存未完成。".to_string())??;
    Ok(Some(name))
}
