//! Versioned authoritative product settings, separate from learning persistence.
use crate::db::models::Id;
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AppSettings {
    pub format_version: u32,
    pub daily_new_word_count: u32,
    pub daily_review_word_count: u32,
    pub randomizes_study_order: bool,
    pub selected_book_id: Option<Id>,
}
impl Default for AppSettings {
    fn default() -> Self {
        Self {
            format_version: 1,
            daily_new_word_count: 10,
            daily_review_word_count: 20,
            randomizes_study_order: true,
            selected_book_id: None,
        }
    }
}
impl AppSettings {
    fn validated(mut self) -> Result<Self, String> {
        if self.format_version != 1 {
            return Err("设置文件版本不受支持，原文件已保留。".into());
        }
        self.daily_new_word_count = self.daily_new_word_count.clamp(1, 100);
        self.daily_review_word_count = self.daily_review_word_count.clamp(1, 200);
        Ok(self)
    }
}
pub struct SettingsStore {
    path: PathBuf,
    value: AppSettings,
}
impl SettingsStore {
    pub fn open(directory: &Path) -> Result<Self, String> {
        let path = directory.join("settings-v1.json");
        let value = match std::fs::read(&path) {
            Ok(bytes) => serde_json::from_slice::<AppSettings>(&bytes)
                .map_err(|_| "本地设置无法读取，原文件已保留。".to_string())?
                .validated()?,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => AppSettings::default(),
            Err(_) => return Err("本地设置无法读取，请检查文件权限。".into()),
        };
        Ok(Self { path, value })
    }
    pub fn get(&self) -> AppSettings {
        self.value.clone()
    }
    pub fn save(&mut self, value: AppSettings) -> Result<AppSettings, String> {
        let value = value.validated()?;
        let bytes = serde_json::to_vec_pretty(&value).map_err(|_| "设置保存失败。".to_string())?;
        atomic_write(&self.path, &bytes).map_err(|_| "设置保存失败，原设置已保留。".to_string())?;
        self.value = value;
        Ok(self.get())
    }
}
/// Same-directory atomic rename; an incomplete write never replaces a saved file.
pub(crate) fn atomic_write(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    use std::io::Write;
    let parent = path.parent().ok_or(std::io::ErrorKind::InvalidInput)?;
    std::fs::create_dir_all(parent)?;
    let temporary = parent.join(format!(".kotoba-write-{}.tmp", uuid::Uuid::new_v4()));
    let result = (|| {
        let mut file = std::fs::OpenOptions::new()
            .create_new(true)
            .write(true)
            .open(&temporary)?;
        file.write_all(bytes)?;
        file.sync_all()?;
        drop(file);
        #[cfg(target_os = "windows")]
        {
            windows_replace(&temporary, path)?;
        }
        #[cfg(not(target_os = "windows"))]
        {
            std::fs::rename(&temporary, path)?;
        }
        Ok(())
    })();
    if result.is_err() {
        let _ = std::fs::remove_file(&temporary);
    }
    result
}
#[cfg(target_os = "windows")]
fn windows_replace(from: &Path, to: &Path) -> std::io::Result<()> {
    use std::os::windows::ffi::OsStrExt;
    #[link(name = "kernel32")]
    extern "system" {
        fn MoveFileExW(from: *const u16, to: *const u16, flags: u32) -> i32;
    }
    let from: Vec<_> = from.as_os_str().encode_wide().chain(Some(0)).collect();
    let to: Vec<_> = to.as_os_str().encode_wide().chain(Some(0)).collect();
    // SAFETY: valid terminated UTF-16 paths; replace-existing and write-through only.
    if unsafe { MoveFileExW(from.as_ptr(), to.as_ptr(), 1 | 8) } == 0 {
        Err(std::io::Error::last_os_error())
    } else {
        Ok(())
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn restart_clamp_and_future_version_preserve_file() {
        let dir = tempfile::tempdir().unwrap();
        let mut store = SettingsStore::open(dir.path()).unwrap();
        assert_eq!(store.get(), AppSettings::default());
        let value = AppSettings {
            daily_new_word_count: 0,
            daily_review_word_count: 1000,
            randomizes_study_order: false,
            selected_book_id: Some(Id::new_local()),
            ..AppSettings::default()
        };
        let saved = store.save(value).unwrap();
        assert_eq!(saved.daily_new_word_count, 1);
        assert_eq!(saved.daily_review_word_count, 200);
        assert_eq!(SettingsStore::open(dir.path()).unwrap().get(), saved);
        let future=b"{\"formatVersion\":2,\"dailyNewWordCount\":10,\"dailyReviewWordCount\":20,\"randomizesStudyOrder\":true,\"selectedBookId\":null}";
        std::fs::write(&store.path, future).unwrap();
        assert!(SettingsStore::open(dir.path()).is_err());
        assert_eq!(std::fs::read(&store.path).unwrap(), future);
    }
    #[test]
    fn failed_write_leaves_memory_and_disk_unchanged() {
        let dir = tempfile::tempdir().unwrap();
        let mut store = SettingsStore::open(dir.path()).unwrap();
        store.save(AppSettings::default()).unwrap();
        let before = store.get();
        store.path = dir.path().join("blocked");
        std::fs::create_dir(&store.path).unwrap();
        let mut value = before.clone();
        value.randomizes_study_order = false;
        assert!(store.save(value).is_err());
        assert_eq!(store.get(), before);
        assert!(store.path.is_dir());
    }
}
