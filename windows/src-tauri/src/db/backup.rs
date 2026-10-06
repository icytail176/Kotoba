//! Windows-local format, explicitly distinct from Mac Backup V3.
//! Canonical IDs map built-ins onto the destination's existing local UUIDs.
use super::{
    models::*,
    repository::{read_learning_progress, read_review_logs, read_vocabulary_words},
    Database, DatabaseError, Result,
};
use crate::vocabulary::Manifest;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Backup {
    pub format: String,
    pub format_version: u32,
    pub database_schema: u32,
    pub manifest_version: Option<u32>,
    pub exported_at: Timestamp,
    pub books: Vec<WordBook>,
    pub words: Vec<VocabularyWord>,
    pub progress: Vec<LearningProgress>,
    pub logs: Vec<ReviewLog>,
}
#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum RestorePolicy {
    Merge,
    SkipExisting,
    Overwrite,
}
#[derive(Debug, Serialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct RestoreSummary {
    pub inserted: u32,
    pub updated: u32,
    pub skipped: u32,
}
fn invalid() -> DatabaseError {
    DatabaseError::InvalidData("invalid or incompatible Windows backup")
}
fn timestamp(t: Timestamp) -> bool {
    (-11_644_473_600_000_000..253_402_300_800_000_000).contains(&t.0)
}
impl Backup {
    pub fn parse(bytes: &[u8]) -> Result<Self> {
        let value: Self = serde_json::from_slice(bytes)?;
        value.validate()?;
        Ok(value)
    }
    pub fn validate(&self) -> Result<()> {
        if self.format != "kotoba-windows-local"
            || self.format_version != 1
            || self.database_schema != 2
            || !timestamp(self.exported_at)
            || self.manifest_version.is_some_and(|v| v != 1)
        {
            return Err(invalid());
        }
        let mut ids = HashSet::new();
        for id in self
            .books
            .iter()
            .map(|b| b.id)
            .chain(self.words.iter().map(|w| w.id))
            .chain(self.progress.iter().map(|p| p.id))
            .chain(self.logs.iter().map(|l| l.id))
        {
            if !ids.insert(id) {
                return Err(invalid());
            }
        }
        let books: HashMap<_, _> = self.books.iter().map(|b| (b.id, b)).collect();
        let words: HashMap<_, _> = self.words.iter().map(|w| (w.id, w)).collect();
        let mut progress_words = HashSet::new();
        let mut canonical = HashSet::new();
        let manifest = Manifest::embedded()?;
        let reserved_books: HashMap<_, _> = manifest
            .books
            .iter()
            .map(|b| (b.canonical_id.as_str(), b.canonical_key.as_str()))
            .collect();
        let reserved_words: HashMap<_, _> = manifest
            .entries
            .iter()
            .map(|w| {
                (
                    w.canonical_id.as_str(),
                    (w.canonical_key.as_str(), w.book_key.as_str()),
                )
            })
            .collect();
        for b in &self.books {
            if b.name.trim().is_empty() || !timestamp(b.created_at) || !timestamp(b.updated_at) {
                return Err(invalid());
            }
            match (&b.canonical_id, &b.canonical_key) {
                (Some(id), Some(key)) if b.is_built_in => {
                    if reserved_books.get(id.to_string().as_str()) != Some(&key.as_str())
                        || !canonical.insert(*id)
                    {
                        return Err(invalid());
                    }
                }
                (None, None) if !b.is_built_in => {}
                _ => return Err(invalid()),
            }
        }
        for w in &self.words {
            if [
                w.japanese.as_str(),
                w.kana.as_str(),
                w.chinese_meaning.as_str(),
            ]
            .iter()
            .any(|s| s.trim().is_empty())
                || !timestamp(w.created_at)
                || !timestamp(w.updated_at)
            {
                return Err(invalid());
            }
            let book = w
                .word_book_id
                .map(|id| books.get(&id).copied().ok_or_else(invalid))
                .transpose()?;
            match (&w.canonical_id, &w.canonical_key) {
                (Some(id), Some(key)) => {
                    let Some((reserved, book_key)) =
                        reserved_words.get(id.to_string().as_str()).copied()
                    else {
                        return Err(invalid());
                    };
                    if reserved != key
                        || book.and_then(|b| b.canonical_key.as_deref()) != Some(book_key)
                        || !canonical.insert(*id)
                    {
                        return Err(invalid());
                    }
                }
                (None, None) => {}
                _ => return Err(invalid()),
            }
        }
        for p in &self.progress {
            if !words.contains_key(&p.word_id)
                || !progress_words.insert(p.word_id)
                || p.interval_days < 0
                || p.interval_days > 60
                || p.review_count < 0
                || p.lapse_count < 0
                || ![p.due_at, p.created_at, p.updated_at]
                    .into_iter()
                    .all(timestamp)
                || p.last_reviewed_at.is_some_and(|t| !timestamp(t))
            {
                return Err(invalid());
            }
        }
        for l in &self.logs {
            if !words.contains_key(&l.word_id)
                || ![l.reviewed_at, l.scheduled_due_at]
                    .into_iter()
                    .all(timestamp)
                || [l.previous_interval_days, l.next_interval_days]
                    .into_iter()
                    .any(|n| !(0..=60).contains(&n))
                || [
                    l.reading_wrong_count,
                    l.spelling_wrong_count,
                    l.repeated_wrong_count,
                ]
                .into_iter()
                .any(|n| n < 0)
                || l.question_direction_raw_value.as_deref().is_some_and(|s| {
                    !matches!(
                        s,
                        "" | "reading"
                            | "expression"
                            | "meaningToExpression"
                            | "expressionToReading"
                    )
                })
            {
                return Err(invalid());
            }
        }
        Ok(())
    }
}
fn should_update(policy: RestorePolicy, incoming: Timestamp, existing: Timestamp) -> bool {
    match policy {
        RestorePolicy::Overwrite => true,
        RestorePolicy::Merge => incoming.0 > existing.0,
        RestorePolicy::SkipExisting => false,
    }
}
impl Database {
    pub fn backup_export(&self, now: Timestamp) -> Result<Backup> {
        let mut stmt=self.connection.prepare("SELECT id,japanese,kana,chinese_meaning,part_of_speech,jlpt_level,example_japanese,example_chinese,tags,created_at,updated_at,is_archived,is_favorite,loanword_source_term,loanword_source_language_code,loanword_is_wasei,loanword_is_partial,word_book_id,canonical_id,canonical_key FROM vocabulary_words ORDER BY id")?;
        let words = stmt
            .query_map([], read_vocabulary_words)?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        let mut stmt=self.connection.prepare("SELECT id,word_id,state,due_at,interval_days,review_count,lapse_count,last_reviewed_at,created_at,updated_at FROM learning_progress ORDER BY id")?;
        let progress = stmt
            .query_map([], read_learning_progress)?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        let mut stmt=self.connection.prepare("SELECT id,word_id,reviewed_at,rating,previous_state,next_state,previous_interval_days,next_interval_days,scheduled_due_at,error_types,typed_answer,expected_answer,question_direction_raw_value,reading_wrong_count,spelling_wrong_count,repeated_wrong_count FROM review_logs ORDER BY id")?;
        let logs = stmt
            .query_map([], read_review_logs)?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        let backup = Backup {
            format: "kotoba-windows-local".into(),
            format_version: 1,
            database_schema: 2,
            manifest_version: self.manifest_version()?,
            exported_at: now,
            books: self.list_books()?,
            words,
            progress,
            logs,
        };
        backup.validate()?;
        Ok(backup)
    }
    pub fn backup_restore(
        &self,
        input: &Backup,
        policy: RestorePolicy,
        confirmed: bool,
    ) -> Result<RestoreSummary> {
        if !confirmed {
            return Err(DatabaseError::InvalidData("confirmation required"));
        }
        input.validate()?;
        // Remap in memory and validate all conflicts before the first database write.
        let local = self.backup_export(input.exported_at)?;
        let book_canonical: HashMap<_, _> = local
            .books
            .iter()
            .filter_map(|b| b.canonical_id.map(|id| (id, b.id)))
            .collect();
        let word_canonical: HashMap<_, _> = local
            .words
            .iter()
            .filter_map(|w| w.canonical_id.map(|id| (id, w.id)))
            .collect();
        let book_map: HashMap<_, _> = input
            .books
            .iter()
            .map(|b| {
                (
                    b.id,
                    b.canonical_id
                        .and_then(|c| book_canonical.get(&c).copied())
                        .unwrap_or(b.id),
                )
            })
            .collect();
        let word_map: HashMap<_, _> = input
            .words
            .iter()
            .map(|w| {
                (
                    w.id,
                    w.canonical_id
                        .and_then(|c| word_canonical.get(&c).copied())
                        .unwrap_or(w.id),
                )
            })
            .collect();
        let progress_by_word: HashMap<_, _> =
            local.progress.iter().map(|p| (p.word_id, p.id)).collect();
        let mut staged = input.clone();
        for b in &mut staged.books {
            b.id = book_map[&b.id];
        }
        for w in &mut staged.words {
            w.id = word_map[&w.id];
            w.word_book_id = w.word_book_id.map(|id| book_map[&id]);
        }
        for p in &mut staged.progress {
            p.word_id = word_map[&p.word_id];
            if let Some(current) = progress_by_word.get(&p.word_id) {
                p.id = *current;
            }
        }
        for l in &mut staged.logs {
            l.word_id = word_map[&l.word_id];
        }
        staged.validate()?;
        let local_books: HashMap<_, _> = local.books.iter().map(|b| (b.id, b)).collect();
        let local_words: HashMap<_, _> = local.words.iter().map(|w| (w.id, w)).collect();
        let local_progress: HashMap<_, _> = local.progress.iter().map(|p| (p.id, p)).collect();
        let local_logs: HashMap<_, _> = local.logs.iter().map(|l| (l.id, l)).collect();
        let mut owners = HashMap::new();
        for id in local_books.keys() {
            owners.insert(*id, 0);
        }
        for id in local_words.keys() {
            owners.insert(*id, 1);
        }
        for id in local_progress.keys() {
            owners.insert(*id, 2);
        }
        for id in local_logs.keys() {
            owners.insert(*id, 3);
        }
        for (id, kind) in staged
            .books
            .iter()
            .map(|b| (b.id, 0))
            .chain(staged.words.iter().map(|w| (w.id, 1)))
            .chain(staged.progress.iter().map(|p| (p.id, 2)))
            .chain(staged.logs.iter().map(|l| (l.id, 3)))
        {
            if owners.get(&id).is_some_and(|owner| *owner != kind) {
                return Err(invalid());
            }
        }
        for b in &staged.books {
            if local_books.get(&b.id).is_some_and(|old| {
                old.canonical_id != b.canonical_id
                    || old.canonical_key != b.canonical_key
                    || old.is_built_in != b.is_built_in
            }) {
                return Err(invalid());
            }
        }
        for w in &staged.words {
            if local_words.get(&w.id).is_some_and(|old| {
                old.canonical_id != w.canonical_id
                    || old.canonical_key != w.canonical_key
                    || old.word_book_id != w.word_book_id
            }) {
                return Err(invalid());
            }
        }
        for p in &staged.progress {
            if local_progress
                .get(&p.id)
                .is_some_and(|old| old.word_id != p.word_id)
            {
                return Err(invalid());
            }
        }
        for l in &staged.logs {
            if local_logs
                .get(&l.id)
                .is_some_and(|old| old.word_id != l.word_id)
            {
                return Err(invalid());
            }
        }
        self.product_transaction(|db| {
            let mut summary = RestoreSummary::default();
            for b in &staged.books {
                match local_books.get(&b.id) {
                    None => {
                        db.upsert_book(b)?;
                        summary.inserted += 1
                    }
                    Some(old) if should_update(policy, b.updated_at, old.updated_at) => {
                        db.upsert_book(b)?;
                        summary.updated += 1
                    }
                    _ => summary.skipped += 1,
                }
            }
            for w in &staged.words {
                match local_words.get(&w.id) {
                    None => {
                        db.upsert_word(w)?;
                        summary.inserted += 1
                    }
                    Some(old) if should_update(policy, w.updated_at, old.updated_at) => {
                        db.upsert_word(w)?;
                        summary.updated += 1
                    }
                    _ => summary.skipped += 1,
                }
            }
            for p in &staged.progress {
                match local_progress.get(&p.id) {
                    None => {
                        db.upsert_progress(p)?;
                        summary.inserted += 1
                    }
                    Some(old) if should_update(policy, p.updated_at, old.updated_at) => {
                        db.upsert_progress(p)?;
                        summary.updated += 1
                    }
                    _ => summary.skipped += 1,
                }
            }
            for l in &staged.logs {
                match local_logs.get(&l.id) {
                    None => {
                        db.insert_log(l)?;
                        summary.inserted += 1
                    }
                    Some(_) if matches!(policy, RestorePolicy::Overwrite) => {
                        db.connection
                            .execute("DELETE FROM review_logs WHERE id=?1", [l.id])?;
                        db.insert_log(l)?;
                        summary.updated += 1
                    }
                    _ => summary.skipped += 1,
                }
            }
            Ok(summary)
        })
    }
}
