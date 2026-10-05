use super::{
    migrations,
    models::*,
    tests::{book, id, log, progress, word},
    Database, DatabaseError,
};
use crate::vocabulary::Manifest;
use rusqlite::{params, Connection};
type TestResult = std::result::Result<(), Box<dyn std::error::Error>>;
const NOW: Timestamp = Timestamp(1_791_114_000_123_456);
fn seeded() -> std::result::Result<(Database, Manifest), Box<dyn std::error::Error>> {
    let m = Manifest::embedded()?;
    let mut db = Database::in_memory()?;
    db.import_builtin(&m, NOW)?;
    Ok((db, m))
}
#[test]
fn native_file_manifest_import_migrate_counts_reopen_and_idempotency() -> TestResult {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("phase3.sqlite3");
    let m = Manifest::embedded()?;
    let canonical = Id::parse(&m.entries[0].canonical_id)?;
    let local;
    {
        let mut db = Database::open(&path)?;
        assert_eq!(db.info()?.schema_version, 2);
        let start = std::time::Instant::now();
        let result = db.import_builtin(&m, NOW)?;
        eprintln!(
            "Fresh 10609-entry import {:?}; one transaction, prepared statements",
            start.elapsed()
        );
        assert_eq!(
            (result.words, result.inserted_words, result.inserted_books),
            (10609, 10609, 5)
        );
        assert_eq!(db.info()?.table_counts.vocabulary_words, 10609);
        assert_eq!(db.manifest_version()?, Some(1));
        let summaries = db.list_builtin_word_books()?;
        assert_eq!(
            summaries.iter().map(|b| b.word_count).collect::<Vec<_>>(),
            vec![802, 755, 1817, 3206, 4029]
        );
        local = db.get_word_by_canonical_id(canonical)?.map(|w| w.id);
        assert!(local.is_some());
        assert_ne!(local, Some(canonical));
    }
    {
        let mut db = Database::open(&path)?;
        let second = db.import_builtin(&m, Timestamp(NOW.0 + 1))?;
        assert_eq!((second.inserted_words, second.inserted_books), (0, 0));
        assert_eq!(db.info()?.table_counts.vocabulary_words, 10609);
        assert_eq!(db.get_word_by_canonical_id(canonical)?.map(|w| w.id), local);
    }
    Ok(())
}
#[test]
fn repeated_import_preserves_all_local_ids_and_user_flags_progress_logs() -> TestResult {
    let (mut db, m) = seeded()?;
    let before: Vec<_> = db
        .list_builtin_word_books()?
        .into_iter()
        .map(|b| b.id)
        .collect();
    let local_ids: Vec<(String, String)> = db
        .connection
        .prepare("SELECT canonical_id,id FROM vocabulary_words ORDER BY canonical_id")?
        .query_map([], |r| Ok((r.get(0)?, r.get(1)?)))?
        .collect::<rusqlite::Result<_>>()?;
    let canonical = Id::parse(&m.entries[0].canonical_id)?;
    let mut w = db
        .get_word_by_canonical_id(canonical)?
        .ok_or("word missing")?;
    w.is_favorite = true;
    w.is_archived = true;
    db.upsert_word(&w)?;
    let p = progress(90001, w.id)?;
    let l = log(90002, w.id, 123)?;
    db.upsert_progress(&p)?;
    db.insert_log(&l)?;
    db.import_builtin(&m, Timestamp(NOW.0 + 100))?;
    assert_eq!(db.get_word_by_canonical_id(canonical)?, Some(w));
    assert_eq!(db.fetch_progress(p.word_id)?, Some(p));
    assert_eq!(db.recent_logs(l.word_id, 10)?, vec![l]);
    assert_eq!(
        db.list_builtin_word_books()?
            .into_iter()
            .map(|b| b.id)
            .collect::<Vec<_>>(),
        before
    );
    let after: Vec<(String, String)> = db
        .connection
        .prepare("SELECT canonical_id,id FROM vocabulary_words ORDER BY canonical_id")?
        .query_map([], |r| Ok((r.get(0)?, r.get(1)?)))?
        .collect::<rusqlite::Result<_>>()?;
    assert_eq!(local_ids, after);
    Ok(())
}
#[test]
fn explicit_new_content_version_updates_lexical_fields_only() -> TestResult {
    let (mut db, mut m) = seeded()?;
    let canonical = Id::parse(&m.entries[0].canonical_id)?;
    let mut w = db.get_word_by_canonical_id(canonical)?.ok_or("missing")?;
    w.is_favorite = true;
    w.is_archived = true;
    db.upsert_word(&w)?;
    let p = progress(90001, w.id)?;
    let l = log(90002, w.id, 1)?;
    db.upsert_progress(&p)?;
    db.insert_log(&l)?;
    m.entries[0].meaning_chinese = "Explicit metadata correction".into();
    m.manifest_version = 2;
    db.import_builtin(&m, Timestamp(NOW.0 + 1))?;
    let updated = db.get_word_by_canonical_id(canonical)?.ok_or("missing")?;
    assert_eq!(updated.chinese_meaning, "Explicit metadata correction");
    assert_eq!(updated.id, w.id);
    assert_eq!(updated.created_at, w.created_at);
    assert!(updated.is_favorite && updated.is_archived);
    assert_eq!(db.fetch_progress(w.id)?, Some(p));
    assert_eq!(db.recent_logs(w.id, 10)?, vec![l]);
    assert_eq!(db.manifest_version()?, Some(2));
    Ok(())
}
#[test]
fn unversioned_content_change_and_downgrade_rejected_without_mutation() -> TestResult {
    let (mut db, mut m) = seeded()?;
    let original = m.clone();
    m.entries[0].meaning_chinese.push('改');
    assert!(db.import_builtin(&m, NOW).is_err());
    assert_eq!(db.manifest_version()?, Some(1));
    m.manifest_version = 2;
    db.import_builtin(&m, NOW)?;
    assert!(db.import_builtin(&original, NOW).is_err());
    assert_eq!(db.manifest_version()?, Some(2));
    Ok(())
}
#[test]
fn import_failure_rolls_back_all_books_words_marker_and_preserves_user_data() -> TestResult {
    let mut db = Database::in_memory()?;
    db.upsert_book(&book()?)?;
    db.upsert_word(&word(2)?)?;
    let p = progress(3, id(2)?)?;
    let l = log(4, id(2)?, 1)?;
    db.upsert_progress(&p)?;
    db.insert_log(&l)?;
    db.connection.execute_batch("CREATE TRIGGER test_import_failure BEFORE INSERT ON vocabulary_words WHEN NEW.canonical_key='jlpt:n3:000900' BEGIN SELECT RAISE(ABORT,'injected middle import failure'); END;")?;
    assert!(db.import_builtin(&Manifest::embedded()?, NOW).is_err());
    assert_eq!(db.info()?.table_counts.word_books, 1);
    assert_eq!(db.info()?.table_counts.vocabulary_words, 1);
    assert_eq!(db.manifest_version()?, None);
    assert_eq!(db.fetch_word(id(2)?)?, Some(word(2)?));
    assert_eq!(db.fetch_progress(id(2)?)?, Some(p));
    assert_eq!(db.recent_logs(id(2)?, 10)?, vec![l]);
    Ok(())
}
#[test]
fn canonical_ids_unique_immutable_and_custom_null_allowed() -> TestResult {
    let (db, m) = seeded()?;
    let canonical = Id::parse(&m.entries[0].canonical_id)?;
    let w = db.get_word_by_canonical_id(canonical)?.ok_or("missing")?;
    let mut duplicate = w.clone();
    duplicate.id = Id::new_local();
    assert!(db.upsert_word(&duplicate).is_err());
    let b = db
        .list_books()?
        .into_iter()
        .find(|b| b.canonical_id.is_some())
        .ok_or("missing book")?;
    let mut duplicate = b.clone();
    duplicate.id = Id::new_local();
    assert!(db.upsert_book(&duplicate).is_err());
    assert!(db
        .connection
        .execute(
            "UPDATE vocabulary_words SET canonical_id=NULL,canonical_key=NULL WHERE id=?1",
            [w.id]
        )
        .is_err());
    let mut change = w.clone();
    change.canonical_id = None;
    change.canonical_key = None;
    assert!(db.upsert_word(&change).is_err());
    db.upsert_book(&book()?)?;
    db.upsert_word(&word(2)?)?;
    assert_eq!(db.fetch_word(id(2)?)?.and_then(|w| w.canonical_id), None);
    Ok(())
}
#[test]
fn schema_one_to_two_preserves_all_four_entity_rows() -> TestResult {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("legacy.sqlite3");
    {
        let mut c = Connection::open(&path)?;
        c.pragma_update(None, "foreign_keys", "ON")?;
        migrations::apply_plan(&mut c, &migrations::MIGRATIONS[..1])?;
        c.execute(
            "INSERT INTO word_books VALUES (?1,'Legacy','keep',1,2,0)",
            [id(1)?],
        )?;
        c.execute("INSERT INTO vocabulary_words VALUES (?1,'語','ご','词','名词','N5','','','[]',1,2,0,1,NULL,NULL,0,0,?2)",params![id(2)?,id(1)?])?;
        c.execute(
            "INSERT INTO learning_progress VALUES (?1,?2,'relearning',99,0,4,2,NULL,1,2)",
            params![id(3)?, id(2)?],
        )?;
        c.execute("INSERT INTO review_logs VALUES (?1,?2,1,'again','review','relearning',60,0,99,'meaning',NULL,NULL,NULL,0,0,0)",params![id(4)?,id(2)?])?;
    }
    let db = Database::open(&path)?;
    assert_eq!(db.info()?.schema_version, 2);
    assert_eq!(
        db.fetch_book(id(1)?)?
            .map(|b| (b.id, b.name, b.canonical_id)),
        Some((id(1)?, "Legacy".into(), None))
    );
    let w = db.fetch_word(id(2)?)?.ok_or("missing legacy word")?;
    assert!(w.is_favorite);
    assert_eq!(w.canonical_id, None);
    assert_eq!(w.word_book_id, Some(id(1)?));
    let p = db.fetch_progress(id(2)?)?.ok_or("missing progress")?;
    assert_eq!(
        (p.state, p.review_count, p.lapse_count),
        (LearningState::Relearning, 4, 2)
    );
    assert_eq!(db.recent_logs(id(2)?, 1)?.len(), 1);
    drop(db);
    assert_eq!(Database::open(&path)?.info()?.schema_version, 2);
    Ok(())
}
#[test]
fn schema_two_migration_failure_rolls_back_columns_and_keeps_legacy_row() -> TestResult {
    let mut c = Connection::open_in_memory()?;
    migrations::apply_plan(&mut c, &migrations::MIGRATIONS[..1])?;
    c.execute(
        "INSERT INTO word_books VALUES (?1,'Keep','',0,0,0)",
        [id(1)?],
    )?;
    c.execute_batch("CREATE TABLE built_in_content(important TEXT); INSERT INTO built_in_content VALUES ('do not delete');")?;
    assert!(matches!(
        migrations::apply(&mut c),
        Err(DatabaseError::Migration { version: 2, .. })
    ));
    assert_eq!(
        c.pragma_query_value(None, "user_version", |r| r.get::<_, u32>(0))?,
        1
    );
    assert!(c.prepare("SELECT canonical_id FROM word_books").is_err());
    assert_eq!(
        c.query_row("SELECT name FROM word_books", [], |r| r.get::<_, String>(0))?,
        "Keep"
    );
    assert_eq!(
        c.query_row("SELECT important FROM built_in_content", [], |r| r
            .get::<_, String>(0))?,
        "do not delete"
    );
    Ok(())
}
#[test]
fn pagination_bounds_book_summary_and_word_lookup() -> TestResult {
    let (db, _) = seeded()?;
    let book = db
        .list_builtin_word_books()?
        .into_iter()
        .next()
        .ok_or("missing")?;
    assert_eq!(
        db.get_word_book_summary(book.id)?.map(|b| b.word_count),
        Some(802)
    );
    let first = db.list_words(book.id, 3, 0)?;
    let next = db.list_words(book.id, 3, 3)?;
    assert_eq!(
        (first.items.len(), next.items.len(), first.total),
        (3, 3, 802)
    );
    assert!(!first
        .items
        .iter()
        .any(|w| next.items.iter().any(|n| n.id == w.id)));
    assert_eq!(
        db.fetch_word(first.items[0].id)?,
        Some(first.items[0].clone())
    );
    assert!(db.list_words(book.id, 0, 0).is_err());
    assert!(db.list_words(book.id, 101, 0).is_err());
    assert!(db.list_words(book.id, 20, 99999)?.items.is_empty());
    Ok(())
}
#[test]
fn substring_search_japanese_reading_chinese_and_literal_sql_wildcards() -> TestResult {
    let (mut db, mut m) = seeded()?;
    for query in ["高校", "こうこう", "高中"] {
        assert!(db.search_words(query, 20, 0)?.total > 0);
    }
    assert_eq!(db.search_words("", 20, 0)?.total, 0);
    assert!(db.search_words(&"a".repeat(201), 20, 0).is_err());
    assert_eq!(db.search_words("' OR 1=1 --", 20, 0)?.total, 0);
    m.entries[0].meaning_chinese = "literal 50% _ \\ test".into();
    m.manifest_version = 2;
    db.import_builtin(&m, NOW)?;
    for query in ["50%", "_", "\\"] {
        let page = db.search_words(query, 20, 0)?;
        assert_eq!(page.total, 1);
        assert_eq!(
            page.items[0].canonical_key,
            Some(m.entries[0].canonical_key.clone())
        );
    }
    Ok(())
}

#[test]
fn missing_manifest_entry_retains_record_identity_and_user_history() -> TestResult {
    let (mut db, mut m) = seeded()?;
    let removed = m.entries.remove(0);
    let canonical = Id::parse(&removed.canonical_id)?;
    let mut w = db.get_word_by_canonical_id(canonical)?.ok_or("missing")?;
    w.is_favorite = true;
    w.is_archived = true;
    db.upsert_word(&w)?;
    let p = progress(90001, w.id)?;
    let l = log(90002, w.id, 1)?;
    db.upsert_progress(&p)?;
    db.insert_log(&l)?;
    m.entry_count -= 1;
    m.books[0].entry_count -= 1;
    m.manifest_version = 2;
    m.retired_keys.push(removed.canonical_key);
    db.import_builtin(&m, NOW)?;
    assert_eq!(db.get_word_by_canonical_id(canonical)?, Some(w.clone()));
    assert_eq!(db.fetch_progress(w.id)?, Some(p));
    assert_eq!(db.recent_logs(w.id, 10)?, vec![l]);
    assert_eq!(db.info()?.table_counts.vocabulary_words, 10609);
    Ok(())
}
