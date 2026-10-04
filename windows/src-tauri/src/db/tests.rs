use super::{migrations, models::*, Database, DatabaseError};
use rusqlite::{params, Connection};
type TestResult<T = ()> = std::result::Result<T, Box<dyn std::error::Error>>;
fn id(n: u128) -> TestResult<Id> {
    Ok(Id::parse(&uuid::Uuid::from_u128(n).to_string())?)
}
fn book() -> TestResult<WordBook> {
    Ok(WordBook {
        id: id(1)?,
        name: "Test".into(),
        book_description: "Temporary".into(),
        created_at: Timestamp(0),
        updated_at: Timestamp(123),
        is_built_in: false,
    })
}
fn word(n: u128) -> TestResult<VocabularyWord> {
    Ok(VocabularyWord {
        id: id(n)?,
        japanese: "ことば".into(),
        kana: "ことば".into(),
        chinese_meaning: "词语".into(),
        part_of_speech: "名词".into(),
        jlpt_level: "N5".into(),
        example_japanese: "日本語".into(),
        example_chinese: "日语".into(),
        tags: vec!["test;tag".into(), "漢字".into()],
        created_at: Timestamp(-1),
        updated_at: Timestamp(1_791_114_000_123_456),
        is_archived: false,
        is_favorite: true,
        loanword_source_term: Some("source".into()),
        loanword_source_language_code: None,
        loanword_is_wasei: true,
        loanword_is_partial: false,
        word_book_id: Some(id(1)?),
    })
}
fn progress(n: u128, word_id: Id) -> TestResult<LearningProgress> {
    Ok(LearningProgress {
        id: id(n)?,
        word_id,
        state: LearningState::Review,
        due_at: Timestamp(1_791_114_000_123_456),
        interval_days: 60,
        review_count: 9,
        lapse_count: 2,
        last_reviewed_at: Some(Timestamp(-1)),
        created_at: Timestamp(0),
        updated_at: Timestamp(321),
    })
}
fn log(n: u128, word_id: Id, date: i64) -> TestResult<ReviewLog> {
    Ok(ReviewLog {
        id: id(n)?,
        word_id,
        reviewed_at: Timestamp(date),
        rating: ReviewRating::Good,
        previous_state: LearningState::Relearning,
        next_state: LearningState::Review,
        previous_interval_days: 0,
        next_interval_days: 2,
        scheduled_due_at: Timestamp(date + 100),
        error_types: vec![ReviewErrorType::Meaning, ReviewErrorType::Reading],
        typed_answer: Some("ご".into()),
        expected_answer: None,
        question_direction_raw_value: Some("reading".into()),
        reading_wrong_count: 1,
        spelling_wrong_count: 2,
        repeated_wrong_count: 3,
    })
}
fn fixture() -> TestResult<Database> {
    let db = Database::in_memory()?;
    db.upsert_book(&book()?)?;
    db.upsert_word(&word(2)?)?;
    Ok(db)
}
#[test]
fn new_database_schema_one_and_empty() -> TestResult {
    let db = Database::in_memory()?;
    assert_eq!(db.info()?.schema_version, 1);
    assert_eq!(db.info()?.table_counts.vocabulary_words, 0);
    assert!(db.list_books()?.is_empty());
    Ok(())
}
#[test]
fn file_backed_migration_crud_reopen_is_idempotent() -> TestResult {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("test.sqlite3");
    let b = book()?;
    let w = word(2)?;
    let p = progress(3, w.id)?;
    let l = log(4, w.id, 111)?;
    {
        let db = Database::open(&path)?;
        db.upsert_book(&b)?;
        db.upsert_word(&w)?;
        db.upsert_progress(&p)?;
        db.insert_log(&l)?;
    }
    {
        let db = Database::open(&path)?;
        assert_eq!(db.info()?.schema_version, 1);
        assert_eq!(db.fetch_book(b.id)?, Some(b));
        assert_eq!(db.fetch_word(w.id)?, Some(w.clone()));
        assert_eq!(db.fetch_progress(w.id)?, Some(p));
        assert_eq!(db.recent_logs(w.id, 10)?, vec![l]);
    }
    Ok(())
}
#[test]
fn foreign_keys_enabled_and_invalid_relationship_rejected() -> TestResult {
    let db = Database::in_memory()?;
    assert_eq!(
        db.connection
            .pragma_query_value(None, "foreign_keys", |r| r.get::<_, i32>(0))?,
        1
    );
    assert!(db.upsert_word(&word(2)?).is_err());
    assert!(db.upsert_progress(&progress(3, id(99)?)?).is_err());
    assert!(db.insert_log(&log(4, id(99)?, 1)?).is_err());
    Ok(())
}
#[test]
fn books_insert_fetch_list_and_explicit_upsert() -> TestResult {
    let db = Database::in_memory()?;
    let mut b = book()?;
    db.upsert_book(&b)?;
    b.name = "Renamed".into();
    b.updated_at = Timestamp(999);
    db.upsert_book(&b)?;
    assert_eq!(db.fetch_book(b.id)?, Some(b.clone()));
    assert_eq!(db.list_books()?, vec![b]);
    assert!(db.fetch_book(id(999)?)?.is_none());
    Ok(())
}
#[test]
fn vocabulary_relationship_optional_metadata_and_upsert_roundtrip() -> TestResult {
    let db = fixture()?;
    let mut w = word(2)?;
    assert_eq!(db.fetch_word(w.id)?, Some(w.clone()));
    assert_eq!(db.words_by_book(id(1)?)?, vec![w.clone()]);
    w.word_book_id = None;
    w.loanword_source_term = None;
    w.japanese = "変更".into();
    db.upsert_word(&w)?;
    assert_eq!(db.fetch_word(w.id)?, Some(w));
    Ok(())
}
#[test]
fn progress_roundtrip_and_one_per_word() -> TestResult {
    let db = fixture()?;
    let mut p = progress(3, id(2)?)?;
    db.upsert_progress(&p)?;
    assert_eq!(db.fetch_progress(id(2)?)?, Some(p.clone()));
    p.last_reviewed_at = None;
    p.state = LearningState::Suspended;
    db.upsert_progress(&p)?;
    assert_eq!(db.fetch_progress(id(2)?)?, Some(p));
    assert!(db.upsert_progress(&progress(4, id(2)?)?).is_err());
    Ok(())
}
#[test]
fn progress_cannot_reparent_and_created_at_is_immutable() -> TestResult {
    let db = fixture()?;
    db.upsert_word(&word(5)?)?;
    let p = progress(3, id(2)?)?;
    db.upsert_progress(&p)?;
    let mut changed = p.clone();
    changed.word_id = id(5)?;
    assert!(matches!(
        db.upsert_progress(&changed),
        Err(DatabaseError::InvalidData(_))
    ));
    changed.word_id = p.word_id;
    changed.created_at = Timestamp(999);
    db.upsert_progress(&changed)?;
    assert_eq!(
        db.fetch_progress(p.word_id)?.map(|p| p.created_at),
        Some(p.created_at)
    );
    Ok(())
}
#[test]
fn logs_append_descending_and_duplicate_id_fails() -> TestResult {
    let db = fixture()?;
    let a = log(4, id(2)?, 10)?;
    let b = log(5, id(2)?, 20)?;
    db.insert_log(&b)?;
    db.insert_log(&a)?;
    assert_eq!(db.recent_logs(id(2)?, 10)?, vec![b.clone(), a]);
    assert_eq!(db.recent_logs(id(2)?, 1)?, vec![b.clone()]);
    assert!(db.insert_log(&b).is_err());
    assert_eq!(db.info()?.table_counts.review_logs, 2);
    Ok(())
}
#[test]
fn delete_one_words_logs_preserves_other_word() -> TestResult {
    let db = fixture()?;
    db.upsert_word(&word(3)?)?;
    db.insert_log(&log(4, id(2)?, 10)?)?;
    let other = log(5, id(3)?, 20)?;
    db.insert_log(&other)?;
    assert_eq!(db.delete_logs_for_word(id(2)?)?, 1);
    assert!(db.recent_logs(id(2)?, 10)?.is_empty());
    assert_eq!(db.recent_logs(id(3)?, 10)?, vec![other]);
    Ok(())
}
#[test]
fn due_query_respects_internal_states_and_day_boundary() -> TestResult {
    let db = fixture()?;
    for (offset, state) in [
        LearningState::New,
        LearningState::Learning,
        LearningState::Relearning,
        LearningState::Review,
        LearningState::Suspended,
    ]
    .into_iter()
    .enumerate()
    {
        let n = offset as u128 + 10;
        db.upsert_word(&word(n)?)?;
        let mut p = progress(n + 100, id(n)?)?;
        p.state = state;
        p.due_at = Timestamp(150);
        db.upsert_progress(&p)?;
    }
    let due = db.due_progress(Timestamp(100), Timestamp(200))?;
    assert_eq!(due.len(), 1);
    assert_eq!(due[0].state, LearningState::Review);
    assert_eq!(db.due_progress(Timestamp(150), Timestamp(150))?.len(), 2);
    Ok(())
}
#[test]
fn canonical_uuid_encoding() -> TestResult {
    let upper = "ABCDEFAB-1234-5678-ABCD-ABCDEFABCDEF";
    let value = Id::parse(upper)?;
    assert_eq!(value.to_string(), upper.to_lowercase());
    assert!(Id::parse("invalid").is_err());
    let db = fixture()?;
    let mut b = book()?;
    b.id = value;
    db.upsert_book(&b)?;
    let raw: String =
        db.connection
            .query_row("SELECT id FROM word_books WHERE id=?1", [value], |r| {
                r.get(0)
            })?;
    assert_eq!(raw, upper.to_lowercase());
    assert!(db
        .connection
        .execute(
            "UPDATE word_books SET id=?1 WHERE id=?2",
            params![upper, value]
        )
        .is_err());
    Ok(())
}
#[test]
fn all_srs_raw_values_roundtrip_and_unknown_rejected() -> TestResult {
    let db = fixture()?;
    for (state, raw) in [
        (LearningState::New, "new"),
        (LearningState::Learning, "learning"),
        (LearningState::Relearning, "relearning"),
        (LearningState::Review, "review"),
        (LearningState::Suspended, "suspended"),
    ] {
        assert_eq!(state.as_str(), raw);
        assert_eq!(LearningState::parse(raw), Some(state));
        let mut p = progress(3, id(2)?)?;
        p.state = state;
        db.upsert_progress(&p)?;
        assert_eq!(db.fetch_progress(id(2)?)?.map(|p| p.state), Some(state));
        assert_eq!(
            db.connection
                .query_row("SELECT state FROM learning_progress", [], |r| r
                    .get::<_, String>(0))?,
            raw
        );
    }
    assert!(LearningState::parse("mastered").is_none());
    assert!(db
        .connection
        .execute("UPDATE learning_progress SET state='mastered'", [])
        .is_err());
    Ok(())
}
#[test]
fn all_rating_raw_values_roundtrip() -> TestResult {
    let db = fixture()?;
    for (offset, (rating, raw)) in [
        (ReviewRating::Again, "again"),
        (ReviewRating::Hard, "hard"),
        (ReviewRating::Good, "good"),
        (ReviewRating::Easy, "easy"),
    ]
    .into_iter()
    .enumerate()
    {
        let mut l = log(offset as u128 + 4, id(2)?, offset as i64)?;
        l.rating = rating;
        db.insert_log(&l)?;
        assert_eq!(rating.as_str(), raw);
        assert_eq!(ReviewRating::parse(raw), Some(rating));
        assert_eq!(db.recent_logs(id(2)?, 1)?[0].rating, rating);
    }
    assert!(ReviewRating::parse("mastered").is_none());
    assert!(db
        .connection
        .execute("UPDATE review_logs SET rating='mastered'", [])
        .is_err());
    Ok(())
}
#[test]
fn timestamp_exact_microseconds_negative_epoch_and_nullable() -> TestResult {
    let db = fixture()?;
    let w = word(2)?;
    let pair: (i64, i64) = db.connection.query_row(
        "SELECT created_at,updated_at FROM vocabulary_words",
        [],
        |r| Ok((r.get(0)?, r.get(1)?)),
    )?;
    assert_eq!(pair, (-1, w.updated_at.0));
    assert_eq!(
        db.fetch_word(id(2)?)?.map(|w| w.updated_at),
        Some(w.updated_at)
    );
    Ok(())
}
#[test]
fn boolean_zero_one_invalid_integer_and_type_rejected() -> TestResult {
    let db = fixture()?;
    let pair: (i64, i64) = db.connection.query_row(
        "SELECT is_archived,is_favorite FROM vocabulary_words",
        [],
        |r| Ok((r.get(0)?, r.get(1)?)),
    )?;
    assert_eq!(pair, (0, 1));
    assert!(db
        .connection
        .execute("UPDATE vocabulary_words SET is_favorite=2", [])
        .is_err());
    assert!(db
        .connection
        .execute("UPDATE vocabulary_words SET is_favorite='true'", [])
        .is_err());
    Ok(())
}
#[test]
fn negative_counters_rejected() -> TestResult {
    let db = fixture()?;
    let mut p = progress(3, id(2)?)?;
    p.review_count = -1;
    assert!(db.upsert_progress(&p).is_err());
    let mut l = log(4, id(2)?, 10)?;
    l.reading_wrong_count = -1;
    assert!(db.insert_log(&l).is_err());
    Ok(())
}
#[test]
fn migration_failure_rolls_back_and_preserves_file() -> TestResult {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("test.sqlite3");
    let db = Database::open(&path)?;
    db.upsert_book(&book()?)?;
    drop(db);
    let mut connection = Connection::open(&path)?;
    let plan=[(1,""),(2,"CREATE TABLE migration_probe(value TEXT); INSERT INTO migration_probe VALUES ('keep'); INVALID SQL;")];
    assert!(matches!(
        migrations::apply_plan(&mut connection, &plan),
        Err(DatabaseError::Migration { version: 2, .. })
    ));
    assert_eq!(
        connection.pragma_query_value(None, "user_version", |r| r.get::<_, i32>(0))?,
        1
    );
    assert_eq!(
        connection.query_row(
            "SELECT count(*) FROM sqlite_master WHERE name='migration_probe'",
            [],
            |r| r.get::<_, i32>(0)
        )?,
        0
    );
    drop(connection);
    let db = Database::open(&path)?;
    assert!(db.fetch_book(id(1)?)?.is_some());
    Ok(())
}
#[test]
fn future_schema_rejected_without_reset() -> TestResult {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("future.sqlite3");
    let db = Database::open(&path)?;
    db.upsert_book(&book()?)?;
    db.connection.pragma_update(None, "user_version", 2)?;
    drop(db);
    assert!(matches!(
        Database::open(&path),
        Err(DatabaseError::UnsupportedSchema(2))
    ));
    let c = Connection::open(&path)?;
    assert_eq!(
        c.query_row("SELECT count(*) FROM word_books", [], |r| r
            .get::<_, i32>(0))?,
        1
    );
    assert_eq!(
        c.pragma_query_value(None, "user_version", |r| r.get::<_, i32>(0))?,
        2
    );
    Ok(())
}
#[test]
fn initial_migration_failure_preserves_unmanaged_data() -> TestResult {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("existing.sqlite3");
    let c = Connection::open(&path)?;
    c.execute_batch("CREATE TABLE vocabulary_words(important TEXT); INSERT INTO vocabulary_words VALUES ('existing user data');")?;
    drop(c);
    assert!(Database::open(&path).is_err());
    let c = Connection::open(&path)?;
    assert_eq!(
        c.query_row("SELECT important FROM vocabulary_words", [], |r| r
            .get::<_, String>(0))?,
        "existing user data"
    );
    assert_eq!(
        c.pragma_query_value(None, "user_version", |r| r.get::<_, i32>(0))?,
        0
    );
    assert_eq!(
        c.query_row(
            "SELECT count(*) FROM sqlite_master WHERE name='word_books'",
            [],
            |r| r.get::<_, i32>(0)
        )?,
        0
    );
    Ok(())
}
#[test]
fn future_migration_one_to_two_preserves_data() -> TestResult {
    let mut db = fixture()?;
    migrations::apply_plan(
        &mut db.connection,
        &[(1, ""), (2, "CREATE TABLE future_metadata(value TEXT);")],
    )?;
    assert_eq!(
        db.connection
            .pragma_query_value(None, "user_version", |r| r.get::<_, i32>(0))?,
        2
    );
    assert!(db.fetch_word(id(2)?)?.is_some());
    Ok(())
}
#[test]
fn errors_sorted_roundtrip_and_tags_preserve_content() -> TestResult {
    let db = fixture()?;
    let mut l = log(4, id(2)?, 10)?;
    l.error_types = vec![
        ReviewErrorType::ExpressionDirection,
        ReviewErrorType::Meaning,
        ReviewErrorType::Reading,
        ReviewErrorType::ReadingDirection,
        ReviewErrorType::Spelling,
    ];
    db.insert_log(&l)?;
    assert_eq!(db.recent_logs(id(2)?, 1)?, vec![l]);
    assert_eq!(
        db.connection
            .query_row("SELECT error_types FROM review_logs", [], |r| r
                .get::<_, String>(0))?,
        "expressionDirection;meaning;reading;readingDirection;spelling"
    );
    assert_eq!(db.fetch_word(id(2)?)?.map(|w| w.tags), Some(word(2)?.tags));
    Ok(())
}
