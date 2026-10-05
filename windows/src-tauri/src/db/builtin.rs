use super::{models::*, Database, DatabaseError, Result};
use crate::vocabulary::Manifest;
use rusqlite::{params, OptionalExtension, TransactionBehavior};
use std::collections::HashMap;

#[derive(Debug, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportResult {
    pub manifest_version: u32,
    pub words: usize,
    pub books: usize,
    pub inserted_words: usize,
    pub inserted_books: usize,
}
impl Database {
    /// Explicit lexical ownership only: never writes user flags, progress or logs.
    pub fn import_builtin(&mut self, manifest: &Manifest, now: Timestamp) -> Result<ImportResult> {
        manifest.validate()?; // All rows validated before acquiring a write transaction.
        let fingerprint = manifest.fingerprint()?;
        let identity_fingerprint = manifest.identity_fingerprint()?;
        let transaction = self
            .connection
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let installed:Option<(u32,String,String)>=transaction.query_row("SELECT manifest_version,namespace_uuid,manifest_fingerprint FROM built_in_content WHERE singleton=1",[],|r| Ok((r.get(0)?,r.get(1)?,r.get(2)?))).optional()?;
        if let Some((version, namespace, hash)) = installed {
            if namespace != manifest.namespace_uuid
                || version > manifest.manifest_version
                || (version == manifest.manifest_version && hash != fingerprint)
            {
                return Err(DatabaseError::InvalidData(
                    "content downgrade, namespace change or unversioned manifest drift",
                ));
            }
        }
        let mut result = ImportResult {
            manifest_version: manifest.manifest_version,
            words: manifest.entries.len(),
            books: manifest.books.len(),
            inserted_words: 0,
            inserted_books: 0,
        };
        let mut book_ids = HashMap::new();
        {
            let mut insert=transaction.prepare("INSERT INTO word_books(id,name,book_description,created_at,updated_at,is_built_in,canonical_id,canonical_key) VALUES (?1,?2,?3,?4,?4,1,?5,?6) ON CONFLICT(canonical_id) WHERE canonical_id IS NOT NULL DO UPDATE SET name=excluded.name,book_description=excluded.book_description,updated_at=excluded.updated_at WHERE word_books.name IS NOT excluded.name OR word_books.book_description IS NOT excluded.book_description")?;
            let mut existing = transaction
                .prepare("SELECT id,canonical_key FROM word_books WHERE canonical_id=?1")?;
            for book in &manifest.books {
                let canonical = Id::parse(&book.canonical_id)
                    .map_err(|_| DatabaseError::InvalidData("invalid canonical book UUID"))?;
                let old: Option<(Id, String)> = existing
                    .query_row([canonical], |r| Ok((r.get(0)?, r.get(1)?)))
                    .optional()?;
                if let Some((_, key)) = &old {
                    if key != &book.canonical_key {
                        return Err(DatabaseError::InvalidData(
                            "book canonical key reassignment",
                        ));
                    }
                }
                insert.execute(params![
                    Id::new_local(),
                    book.name,
                    book.description,
                    now,
                    canonical,
                    book.canonical_key
                ])?;
                let (id, _): (Id, String) =
                    existing.query_row([canonical], |r| Ok((r.get(0)?, r.get(1)?)))?;
                if old.is_none() {
                    result.inserted_books += 1;
                }
                book_ids.insert(book.canonical_key.as_str(), id);
            }
        }
        {
            let mut identities_query=transaction.prepare("SELECT canonical_id,canonical_key FROM vocabulary_words WHERE canonical_id IS NOT NULL")?;
            let existing_identities = identities_query
                .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))?
                .collect::<rusqlite::Result<HashMap<_, _>>>()?;
            for entry in &manifest.entries {
                if existing_identities
                    .get(&entry.canonical_id)
                    .is_some_and(|key| key != &entry.canonical_key)
                {
                    return Err(DatabaseError::InvalidData(
                        "word canonical key reassignment",
                    ));
                }
            }
            let before: i64 = transaction.query_row(
                "SELECT count(*) FROM vocabulary_words WHERE canonical_id IS NOT NULL",
                [],
                |r| r.get(0),
            )?;
            let mut insert=transaction.prepare("INSERT INTO vocabulary_words(id,japanese,kana,chinese_meaning,part_of_speech,jlpt_level,example_japanese,example_chinese,tags,created_at,updated_at,is_archived,is_favorite,loanword_source_term,loanword_source_language_code,loanword_is_wasei,loanword_is_partial,word_book_id,canonical_id,canonical_key) VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?10,0,0,?11,?12,?13,?14,?15,?16,?17) ON CONFLICT(canonical_id) WHERE canonical_id IS NOT NULL DO UPDATE SET japanese=excluded.japanese,kana=excluded.kana,chinese_meaning=excluded.chinese_meaning,part_of_speech=excluded.part_of_speech,jlpt_level=excluded.jlpt_level,example_japanese=excluded.example_japanese,example_chinese=excluded.example_chinese,tags=excluded.tags,loanword_source_term=excluded.loanword_source_term,loanword_source_language_code=excluded.loanword_source_language_code,loanword_is_wasei=excluded.loanword_is_wasei,loanword_is_partial=excluded.loanword_is_partial,word_book_id=excluded.word_book_id,updated_at=excluded.updated_at WHERE vocabulary_words.japanese IS NOT excluded.japanese OR vocabulary_words.kana IS NOT excluded.kana OR vocabulary_words.chinese_meaning IS NOT excluded.chinese_meaning OR vocabulary_words.part_of_speech IS NOT excluded.part_of_speech OR vocabulary_words.jlpt_level IS NOT excluded.jlpt_level OR vocabulary_words.example_japanese IS NOT excluded.example_japanese OR vocabulary_words.example_chinese IS NOT excluded.example_chinese OR vocabulary_words.tags IS NOT excluded.tags OR vocabulary_words.loanword_source_term IS NOT excluded.loanword_source_term OR vocabulary_words.loanword_source_language_code IS NOT excluded.loanword_source_language_code OR vocabulary_words.loanword_is_wasei IS NOT excluded.loanword_is_wasei OR vocabulary_words.loanword_is_partial IS NOT excluded.loanword_is_partial OR vocabulary_words.word_book_id IS NOT excluded.word_book_id")?;
            for entry in &manifest.entries {
                let book = book_ids
                    .get(entry.book_key.as_str())
                    .ok_or(DatabaseError::InvalidData("missing import book"))?;
                let canonical = Id::parse(&entry.canonical_id)
                    .map_err(|_| DatabaseError::InvalidData("invalid canonical word UUID"))?;
                insert.execute(params![
                    Id::new_local(),
                    entry.expression,
                    entry.reading,
                    entry.meaning_chinese,
                    entry.part_of_speech,
                    entry.jlpt_level,
                    entry.example_japanese,
                    entry.example_chinese,
                    serde_json::to_string(&entry.tags)?,
                    now,
                    entry.loanword_source_term,
                    entry.loanword_source_language_code,
                    entry.loanword_is_wasei,
                    entry.loanword_is_partial,
                    book,
                    canonical,
                    entry.canonical_key
                ])?;
            }
            let after: i64 = transaction.query_row(
                "SELECT count(*) FROM vocabulary_words WHERE canonical_id IS NOT NULL",
                [],
                |r| r.get(0),
            )?;
            result.inserted_words = usize::try_from(after - before)
                .map_err(|_| DatabaseError::InvalidData("import unexpectedly removed words"))?;
        }
        // Missing older identities are retained with user state unchanged, never hard-deleted.
        transaction.execute("INSERT INTO built_in_content(singleton,manifest_version,format_version,namespace_uuid,manifest_fingerprint,identity_fingerprint) VALUES (1,?1,?2,?3,?4,?5) ON CONFLICT(singleton) DO UPDATE SET manifest_version=excluded.manifest_version,format_version=excluded.format_version,manifest_fingerprint=excluded.manifest_fingerprint,identity_fingerprint=excluded.identity_fingerprint",params![manifest.manifest_version,manifest.format_version,manifest.namespace_uuid,fingerprint,identity_fingerprint])?;
        for book in &manifest.books {
            let count:i64=transaction.query_row("SELECT count(*) FROM vocabulary_words WHERE word_book_id=?1 AND canonical_id IS NOT NULL",[book_ids[book.canonical_key.as_str()]],|r|r.get(0))?;
            if manifest.manifest_version == 1 && count != book.entry_count as i64 {
                return Err(DatabaseError::InvalidData("imported book count mismatch"));
            }
        }
        transaction.commit()?;
        Ok(result)
    }
    pub fn manifest_version(&self) -> Result<Option<u32>> {
        Ok(self
            .connection
            .query_row(
                "SELECT manifest_version FROM built_in_content WHERE singleton=1",
                [],
                |r| r.get(0),
            )
            .optional()?)
    }
}
