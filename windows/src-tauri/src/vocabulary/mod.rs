//! Checked-in canonical identity. Runtime has no repository/file path dependency.
use crate::db::{DatabaseError, Result};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap, HashSet};

pub const NAMESPACE: uuid::Uuid = uuid::uuid!("01dfa402-05c2-46ab-a30f-acd35aa26ac0");
pub const EMBEDDED_MANIFEST: &str =
    include_str!("../../../../shared/vocabulary/canonical_vocabulary.json");
const EMBEDDED_LEDGER: &str =
    include_str!("../../../../shared/vocabulary/canonical_identity_ledger.json");
const COUNTS: [(&str, &str, usize); 5] = [
    ("jlpt-n5", "N5", 802),
    ("jlpt-n4", "N4", 755),
    ("jlpt-n3", "N3", 1817),
    ("jlpt-n2", "N2", 3206),
    ("jlpt-n1", "N1", 4029),
];

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Book {
    pub canonical_key: String,
    pub canonical_id: String,
    pub identity_anchor: String,
    pub name: String,
    pub description: String,
    pub jlpt_level: String,
    pub entry_count: usize,
}
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Entry {
    pub canonical_key: String,
    pub canonical_id: String,
    pub identity_anchor: String,
    pub book_key: String,
    pub expression: String,
    pub reading: String,
    pub meaning_chinese: String,
    pub part_of_speech: String,
    pub jlpt_level: String,
    pub example_japanese: String,
    pub example_chinese: String,
    pub tags: Vec<String>,
    pub loanword_source_term: Option<String>,
    pub loanword_source_language_code: Option<String>,
    pub loanword_is_wasei: bool,
    pub loanword_is_partial: bool,
}
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Source {
    pub source_mac_seed_version: u32,
    pub pipeline: String,
    pub source_sha256: BTreeMap<String, String>,
}
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Manifest {
    pub format_version: u32,
    pub manifest_version: u32,
    #[serde(rename = "namespaceUUID")]
    pub namespace_uuid: String,
    pub generated_from: Source,
    pub entry_count: usize,
    pub books: Vec<Book>,
    pub entries: Vec<Entry>,
    pub created_at: String,
    pub retired_keys: Vec<String>,
}
#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Ledger {
    format_version: u32,
    #[serde(rename = "namespaceUUID")]
    namespace_uuid: String,
    identities: Vec<(String, String, String)>,
}
fn invalid(message: impl Into<String>) -> DatabaseError {
    DatabaseError::Manifest(message.into())
}
fn canonical(key: &str, id: &str, anchor: &str, book: bool) -> Result<()> {
    if key.trim().is_empty()
        || anchor.len() != 64
        || !anchor
            .bytes()
            .all(|c| c.is_ascii_hexdigit() && !c.is_ascii_uppercase())
    {
        return Err(invalid(format!("invalid identity key/anchor: {key}")));
    }
    let name = if book {
        format!("book:{key}")
    } else {
        key.to_string()
    };
    if uuid::Uuid::new_v5(&NAMESPACE, name.as_bytes()).to_string() != id {
        return Err(invalid(format!(
            "UUID v5/canonical encoding mismatch: {key}"
        )));
    }
    Ok(())
}
impl Manifest {
    pub fn parse(text: &str) -> Result<Self> {
        let manifest: Self = serde_json::from_str(text)?;
        manifest.validate()?;
        Ok(manifest)
    }
    pub fn embedded() -> Result<Self> {
        Self::parse(EMBEDDED_MANIFEST)
    }
    pub fn validate(&self) -> Result<()> {
        if self.format_version != 1
            || self.manifest_version == 0
            || self.namespace_uuid != NAMESPACE.to_string()
            || self.generated_from.source_mac_seed_version != 8
            || self.generated_from.pipeline.trim().is_empty()
            || self.created_at.trim().is_empty()
            || self.entry_count != self.entries.len()
            || self.books.len() != 5
        {
            return Err(invalid(
                "invalid format/version/namespace/source/count metadata",
            ));
        }
        let ledger: Ledger = serde_json::from_str(EMBEDDED_LEDGER)?;
        if ledger.format_version != 1 || ledger.namespace_uuid != self.namespace_uuid {
            return Err(invalid("identity ledger namespace mismatch"));
        }
        let reservations: HashMap<_, _> = ledger
            .identities
            .iter()
            .map(|(key, id, anchor)| (key.as_str(), (id.as_str(), anchor.as_str())))
            .collect();
        if reservations.len() != ledger.identities.len() {
            return Err(invalid("duplicate reserved identity key"));
        }
        let mut keys = HashSet::new();
        let mut ids = HashSet::new();
        let mut check_identity = |key: &str, id: &str, anchor: &str, book: bool| -> Result<()> {
            canonical(key, id, anchor, book)?;
            if !keys.insert(key.to_string()) || !ids.insert(id.to_string()) {
                return Err(invalid("duplicate canonical identity"));
            }
            if reservations.get(key) != Some(&(id, anchor)) {
                return Err(invalid(format!("unreserved or reassigned identity: {key}")));
            }
            Ok(())
        };
        for book in &self.books {
            check_identity(
                &book.canonical_key,
                &book.canonical_id,
                &book.identity_anchor,
                true,
            )?;
            if book.name.trim().is_empty()
                || !COUNTS
                    .iter()
                    .any(|(key, level, _)| book.canonical_key == *key && book.jlpt_level == *level)
            {
                return Err(invalid("invalid/unknown book"));
            }
        }
        let books: HashMap<_, _> = self
            .books
            .iter()
            .map(|b| (b.canonical_key.as_str(), b))
            .collect();
        let mut counts: HashMap<&str, usize> = HashMap::new();
        for entry in &self.entries {
            check_identity(
                &entry.canonical_key,
                &entry.canonical_id,
                &entry.identity_anchor,
                false,
            )?;
            let book = books
                .get(entry.book_key.as_str())
                .ok_or_else(|| invalid("unknown entry book"))?;
            if entry.expression.trim().is_empty()
                || entry.reading.trim().is_empty()
                || entry.meaning_chinese.trim().is_empty()
                || entry.jlpt_level != book.jlpt_level
            {
                return Err(invalid(format!(
                    "invalid lexical fields: {}",
                    entry.canonical_key
                )));
            }
            *counts.entry(entry.book_key.as_str()).or_default() += 1;
        }
        // Removed identities stay permanently reserved; no guessing or reassignment.
        let retired: HashSet<_> = self.retired_keys.iter().map(String::as_str).collect();
        if retired.len() != self.retired_keys.len()
            || reservations
                .keys()
                .filter(|key| !keys.contains(**key))
                .copied()
                .collect::<HashSet<_>>()
                != retired
        {
            return Err(invalid("invalid retired/reserved identities"));
        }
        for (key, _, expected) in COUNTS {
            let book = books.get(key).ok_or_else(|| invalid("missing book"))?;
            if counts.get(key).copied().unwrap_or_default() != book.entry_count
                || (self.manifest_version == 1 && book.entry_count != expected)
            {
                return Err(invalid(format!("book entry count mismatch: {key}")));
            }
        }
        if self.manifest_version == 1 && self.entry_count != 10609 {
            return Err(invalid("v1 must contain 10609 entries"));
        }
        Ok(())
    }
    /// Version fingerprint only, not a security signature or a lexical ID algorithm.
    pub fn fingerprint(&self) -> Result<String> {
        let mut books = self.books.clone();
        books.sort_by(|a, b| a.canonical_key.cmp(&b.canonical_key));
        let mut entries = self.entries.clone();
        entries.sort_by(|a, b| a.canonical_key.cmp(&b.canonical_key));
        let bytes = serde_json::to_vec(&(
            self.format_version,
            self.manifest_version,
            &books,
            &entries,
            &self.retired_keys,
        ))?;
        Ok(uuid::Uuid::new_v5(&NAMESPACE, &bytes).to_string())
    }
    pub fn identity_fingerprint(&self) -> Result<String> {
        let mut identities: Vec<_> = self
            .books
            .iter()
            .map(|b| (&b.canonical_key, &b.canonical_id))
            .chain(
                self.entries
                    .iter()
                    .map(|e| (&e.canonical_key, &e.canonical_id)),
            )
            .collect();
        identities.sort_unstable();
        Ok(uuid::Uuid::new_v5(&NAMESPACE, &serde_json::to_vec(&identities)?).to_string())
    }
}
#[cfg(test)]
mod tests;
