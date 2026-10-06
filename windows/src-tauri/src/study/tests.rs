use super::time::*;
use crate::db::models::Timestamp;
#[test]
fn civil_time_conversion_is_checked_and_host_independent() {
    for (y, m, d) in [
        (1970, 1, 1),
        (2026, 3, 8),
        (2026, 11, 1),
        (2026, 12, 31),
        (2028, 2, 29),
    ] {
        let instant = Timestamp(civil_micros(y, m, d, 23, 59, 59).expect("valid"));
        assert_eq!(utc_parts(instant).expect("parts"), (y, m, d, 23, 59, 59));
    }
    assert_eq!(civil_micros(1970, 1, 1, 0, 0, 0).expect("epoch"), 0);
    assert!(civil_micros(2026, 2, 29, 0, 0, 0).is_err());
    assert!(civil_micros(2026, 13, 1, 0, 0, 0).is_err());
    assert!(civil_micros(2026, 1, 1, 24, 0, 0).is_err());
}

use super::{
    models::*,
    queue::{self, QueuePolicy},
    service,
};
use crate::{
    db::{models::*, Database},
    srs::calendar::CalendarContext,
};
type TestResult<T = ()> = std::result::Result<T, Box<dyn std::error::Error>>;
const NOW: Timestamp = Timestamp(1_790_000_000_000_000);
fn seed(db: &Database) -> TestResult<(Id, Vec<Id>)> {
    let book = WordBook {
        id: Id::new_local(),
        name: "Temporary N5".into(),
        book_description: "test only".into(),
        created_at: Timestamp(0),
        updated_at: Timestamp(0),
        is_built_in: false,
        canonical_id: None,
        canonical_key: None,
    };
    db.upsert_book(&book)?;
    let mut ids = Vec::new();
    for (expression, reading) in [
        ("食べる", "たべる"),
        ("確認", "かくにん"),
        ("かな", "かな"),
        ("学生", "がくせい"),
    ] {
        let word = VocabularyWord {
            id: Id::new_local(),
            japanese: expression.into(),
            kana: reading.into(),
            chinese_meaning: "测试释义".into(),
            part_of_speech: "名词".into(),
            jlpt_level: "N5".into(),
            example_japanese: format!("{expression}。"),
            example_chinese: "例句".into(),
            tags: vec![],
            created_at: Timestamp(ids.len() as i64),
            updated_at: Timestamp(0),
            is_archived: false,
            is_favorite: false,
            loanword_source_term: None,
            loanword_source_language_code: None,
            loanword_is_wasei: false,
            loanword_is_partial: false,
            word_book_id: Some(book.id),
            canonical_id: None,
            canonical_key: None,
        };
        db.upsert_word(&word)?;
        ids.push(word.id);
    }
    Ok((book.id, ids))
}
fn p(word: Id, state: LearningState) -> LearningProgress {
    LearningProgress {
        id: Id::new_local(),
        word_id: word,
        state,
        due_at: NOW,
        interval_days: 60,
        review_count: 9,
        lapse_count: 2,
        last_reviewed_at: Some(Timestamp(NOW.0 - 100)),
        created_at: Timestamp(0),
        updated_at: Timestamp(0),
    }
}
fn previous_good(db: &Database, word: Id) -> TestResult {
    db.insert_log(&ReviewLog {
        id: Id::new_local(),
        word_id: word,
        reviewed_at: Timestamp(NOW.0 - 100),
        rating: ReviewRating::Good,
        previous_state: LearningState::Review,
        next_state: LearningState::Review,
        previous_interval_days: 32,
        next_interval_days: 60,
        scheduled_due_at: NOW,
        error_types: vec![],
        typed_answer: None,
        expected_answer: None,
        question_direction_raw_value: None,
        reading_wrong_count: 0,
        spelling_wrong_count: 0,
        repeated_wrong_count: 0,
    })?;
    Ok(())
}
fn formal(db: &mut Database, word: Id, rating: ReviewRating) -> TestResult<FormalCommit> {
    let expected = db.fetch_progress(word)?;
    Ok(service::formal(
        db,
        FormalRequest {
            word_id: word,
            expected_progress: expected,
            rating,
            now: NOW,
        },
        &CalendarContext::fixed(28800)?,
    )?)
}
fn enrichment(word: Id, log: Id) -> Enrichment {
    Enrichment {
        word_id: word,
        log_id: log,
        typed_answer: Some("错误".into()),
        expected_answer: Some("がくせい".into()),
        question_direction_raw_value: Some("expressionToReading".into()),
        reading_wrong_count: 1,
        spelling_wrong_count: 2,
    }
}
#[test]
fn queue_modes_limits_scope_and_empty_state_match_source() -> TestResult {
    let db = Database::in_memory()?;
    let (book, ids) = seed(&db)?;
    let calendar = CalendarContext::fixed(28800)?;
    db.upsert_progress(&p(ids[0], LearningState::Review))?;
    db.upsert_progress(&p(ids[1], LearningState::Learning))?;
    let policy = || QueuePolicy {
        new_limit: 1,
        review_limit: 1,
        randomizes: false,
    };
    let mixed = queue::start(
        &db,
        book,
        SessionMode::Mixed,
        NOW,
        &calendar,
        policy(),
        "Injected".into(),
    )?;
    assert_eq!(mixed.cards.len(), 2);
    assert_eq!(mixed.cards[0].kind, CardKind::DueReview);
    assert_eq!(mixed.cards[1].kind, CardKind::NewWord);
    assert!(mixed.cards[0].expected_progress.is_some());
    assert!(mixed.cards[1].expected_progress.is_none());
    for (mode, kind) in [
        (SessionMode::NewWordsOnly, CardKind::NewWord),
        (SessionMode::DueReviewsOnly, CardKind::DueReview),
    ] {
        let result = queue::start(&db, book, mode, NOW, &calendar, policy(), "Injected".into())?;
        assert_eq!(result.cards.len(), 1);
        assert_eq!(result.cards[0].kind, kind);
    }
    let empty = WordBook {
        id: Id::new_local(),
        name: "empty".into(),
        book_description: String::new(),
        created_at: NOW,
        updated_at: NOW,
        is_built_in: false,
        canonical_id: None,
        canonical_key: None,
    };
    db.upsert_book(&empty)?;
    assert!(queue::start(
        &db,
        empty.id,
        SessionMode::Mixed,
        NOW,
        &calendar,
        policy(),
        "Injected".into()
    )?
    .cards
    .is_empty());
    assert!(queue::start(
        &db,
        Id::new_local(),
        SessionMode::Mixed,
        NOW,
        &calendar,
        policy(),
        "Injected".into()
    )
    .is_err());
    Ok(())
}
#[test]
fn queue_archived_suspended_and_minute_future_excluded_review_later_today_included() -> TestResult {
    let db = Database::in_memory()?;
    let (book, ids) = seed(&db)?;
    let calendar = CalendarContext::fixed(28800)?;
    let mut archived = db.fetch_word(ids[0])?.ok_or("missing")?;
    archived.is_archived = true;
    db.upsert_word(&archived)?;
    db.upsert_progress(&p(ids[1], LearningState::Suspended))?;
    let mut minute = p(ids[2], LearningState::Relearning);
    minute.due_at = Timestamp(NOW.0 + 1);
    db.upsert_progress(&minute)?;
    let mut review = p(ids[3], LearningState::Review);
    review.due_at = Timestamp(calendar.day_end_exclusive(NOW)?.0 - 1);
    db.upsert_progress(&review)?;
    let availability = queue::availability(&db, book, NOW, &calendar, "Injected".into())?;
    assert_eq!(
        (
            availability.new_count,
            availability.due_count,
            availability.total_count,
            availability.reviewing_count,
            availability.mastered_count
        ),
        (0, 1, 3, 2, 1)
    );
    let session = queue::start(
        &db,
        book,
        SessionMode::Mixed,
        NOW,
        &calendar,
        QueuePolicy::default(),
        "Injected".into(),
    )?;
    assert_eq!(session.cards.len(), 1);
    assert_eq!(session.cards[0].word.word.id, ids[3]);
    Ok(())
}
#[test]
fn randomized_mixed_queue_retains_independent_group_caps() -> TestResult {
    let db = Database::in_memory()?;
    let (book, ids) = seed(&db)?;
    for id in &ids[..2] {
        db.upsert_progress(&p(*id, LearningState::Review))?;
    }
    let session = queue::start(
        &db,
        book,
        SessionMode::Mixed,
        NOW,
        &CalendarContext::fixed(-28800)?,
        QueuePolicy {
            new_limit: 1,
            review_limit: 1,
            randomizes: true,
        },
        "Injected".into(),
    )?;
    assert_eq!(
        session
            .cards
            .iter()
            .filter(|c| c.kind == CardKind::NewWord)
            .count(),
        1
    );
    assert_eq!(
        session
            .cards
            .iter()
            .filter(|c| c.kind == CardKind::DueReview)
            .count(),
        1
    );
    Ok(())
}
#[test]
fn study_formal_failure_retry_stale_and_one_log_cardinality() -> TestResult {
    let mut db = Database::in_memory()?;
    let (_, ids) = seed(&db)?;
    db.connection.execute_batch("CREATE TEMP TRIGGER fail_formal BEFORE INSERT ON review_logs BEGIN SELECT RAISE(ABORT,'injected'); END;")?;
    assert_eq!(
        service::formal(
            &mut db,
            FormalRequest {
                word_id: ids[0],
                expected_progress: None,
                rating: ReviewRating::Good,
                now: NOW
            },
            &CalendarContext::fixed(0)?
        )
        .expect_err("failure")
        .code,
        "save"
    );
    assert!(db.fetch_progress(ids[0])?.is_none());
    assert!(db.recent_logs(ids[0], 10)?.is_empty());
    db.connection.execute_batch("DROP TRIGGER fail_formal;")?;
    let committed = formal(&mut db, ids[0], ReviewRating::Good)?;
    assert_eq!(committed.progress.review_count, 1);
    assert_eq!(db.recent_logs(ids[0], 10)?.len(), 1);
    assert_eq!(
        service::formal(
            &mut db,
            FormalRequest {
                word_id: ids[0],
                expected_progress: None,
                rating: ReviewRating::Good,
                now: NOW
            },
            &CalendarContext::fixed(0)?
        )
        .expect_err("stale")
        .code,
        "stale"
    );
    assert_eq!(db.recent_logs(ids[0], 10)?.len(), 1);
    Ok(())
}
#[test]
fn reinforcement_mastery_preserves_formal_log_counters_and_last_reviewed() -> TestResult {
    let mut db = Database::in_memory()?;
    let (_, ids) = seed(&db)?;
    let committed = formal(&mut db, ids[0], ReviewRating::Again)?;
    let logs = db.recent_logs(ids[0], 10)?;
    let next = service::reinforcement_mastered(
        &mut db,
        ids[0],
        committed.progress.clone(),
        Timestamp(NOW.0 + 10),
    )?;
    assert_eq!(next.state, LearningState::Suspended);
    assert_eq!(next.interval_days, 0);
    assert_eq!(next.due_at, Timestamp(NOW.0 + 10));
    assert_eq!(
        (next.review_count, next.lapse_count, next.last_reviewed_at),
        (
            committed.progress.review_count,
            committed.progress.lapse_count,
            committed.progress.last_reviewed_at
        )
    );
    assert_eq!(db.recent_logs(ids[0], 10)?, logs);
    Ok(())
}
#[test]
fn reinforcement_mastery_after_progress_failure_rolls_back_then_retries() -> TestResult {
    let mut db = Database::in_memory()?;
    let (_, ids) = seed(&db)?;
    let committed = formal(&mut db, ids[0], ReviewRating::Again)?;
    let before = db.fetch_word(ids[0])?;
    let logs = db.recent_logs(ids[0], 10)?;
    db.connection.execute_batch("CREATE TEMP TRIGGER fail_word AFTER UPDATE OF updated_at ON vocabulary_words BEGIN SELECT RAISE(ABORT,'injected'); END;")?;
    assert!(service::reinforcement_mastered(
        &mut db,
        ids[0],
        committed.progress.clone(),
        Timestamp(NOW.0 + 20)
    )
    .is_err());
    assert_eq!(db.fetch_progress(ids[0])?, Some(committed.progress.clone()));
    assert_eq!(db.fetch_word(ids[0])?, before);
    assert_eq!(db.recent_logs(ids[0], 10)?, logs);
    db.connection.execute_batch("DROP TRIGGER fail_word;")?;
    service::reinforcement_mastered(&mut db, ids[0], committed.progress, Timestamp(NOW.0 + 20))?;
    assert_eq!(db.recent_logs(ids[0], 10)?, logs);
    Ok(())
}
#[test]
fn favorite_persists_without_scheduler_or_logs_and_sql_failure_rolls_back() -> TestResult {
    let mut db = Database::in_memory()?;
    let (_, ids) = seed(&db)?;
    formal(&mut db, ids[0], ReviewRating::Hard)?;
    let progress = db.fetch_progress(ids[0])?;
    let logs = db.recent_logs(ids[0], 10)?;
    assert!(service::favorite(&mut db, ids[0], false, NOW)?);
    assert_eq!(db.fetch_progress(ids[0])?, progress);
    assert_eq!(db.recent_logs(ids[0], 10)?, logs);
    db.connection.execute_batch("CREATE TEMP TRIGGER fail_favorite AFTER UPDATE OF is_favorite ON vocabulary_words BEGIN SELECT RAISE(ABORT,'injected'); END;")?;
    assert!(service::favorite(&mut db, ids[0], true, Timestamp(NOW.0 + 10)).is_err());
    assert!(db.fetch_word(ids[0])?.ok_or("word")?.is_favorite);
    assert_eq!(db.fetch_progress(ids[0])?, progress);
    assert_eq!(db.recent_logs(ids[0], 10)?, logs);
    Ok(())
}
#[test]
fn enrichment_updates_original_log_only_preserves_transition_and_repeated_counter() -> TestResult {
    let mut db = Database::in_memory()?;
    let (_, ids) = seed(&db)?;
    let committed = formal(&mut db, ids[0], ReviewRating::Again)?;
    db.connection.execute(
        "UPDATE review_logs SET repeated_wrong_count = 23 WHERE id = ?1",
        [committed.log_id.to_string()],
    )?;
    let before = db.recent_logs(ids[0], 10)?[0].clone();
    let progress = db.fetch_progress(ids[0])?;
    service::enrich(&mut db, vec![enrichment(ids[0], committed.log_id)])?;
    let logs = db.recent_logs(ids[0], 10)?;
    assert_eq!(logs.len(), 1);
    let log = &logs[0];
    assert_eq!(
        (
            log.id,
            log.rating,
            log.reviewed_at,
            log.previous_state,
            log.next_state,
            log.previous_interval_days,
            log.next_interval_days,
            log.scheduled_due_at,
            log.repeated_wrong_count
        ),
        (
            before.id,
            before.rating,
            before.reviewed_at,
            before.previous_state,
            before.next_state,
            before.previous_interval_days,
            before.next_interval_days,
            before.scheduled_due_at,
            before.repeated_wrong_count
        )
    );
    assert_eq!((log.spelling_wrong_count, log.reading_wrong_count), (2, 1));
    assert_eq!(log.typed_answer.as_deref(), Some("错误"));
    assert_eq!(
        log.question_direction_raw_value.as_deref(),
        Some("expressionToReading")
    );
    for error in [
        ReviewErrorType::Meaning,
        ReviewErrorType::Spelling,
        ReviewErrorType::Reading,
        ReviewErrorType::ExpressionDirection,
        ReviewErrorType::ReadingDirection,
    ] {
        assert!(log.error_types.contains(&error));
    }
    assert_eq!(db.fetch_progress(ids[0])?, progress);
    service::enrich(&mut db, vec![enrichment(ids[0], committed.log_id)])?;
    assert_eq!(db.recent_logs(ids[0], 10)?, logs);
    Ok(())
}
#[test]
fn multiple_enrichment_updates_roll_back_together_then_retry() -> TestResult {
    let mut db = Database::in_memory()?;
    let (_, ids) = seed(&db)?;
    let a = formal(&mut db, ids[0], ReviewRating::Good)?;
    let b = formal(&mut db, ids[1], ReviewRating::Hard)?;
    let before_a = db.recent_logs(ids[0], 10)?;
    let before_b = db.recent_logs(ids[1], 10)?;
    db.connection.execute_batch(&format!("CREATE TEMP TRIGGER fail_second BEFORE UPDATE ON review_logs WHEN OLD.id='{}' BEGIN SELECT RAISE(ABORT,'injected'); END;",b.log_id))?;
    let entries = vec![enrichment(ids[0], a.log_id), enrichment(ids[1], b.log_id)];
    assert!(service::enrich(&mut db, entries.clone()).is_err());
    assert_eq!(db.recent_logs(ids[0], 10)?, before_a);
    assert_eq!(db.recent_logs(ids[1], 10)?, before_b);
    db.connection.execute_batch("DROP TRIGGER fail_second;")?;
    service::enrich(&mut db, entries)?;
    assert_eq!(db.info()?.table_counts.review_logs, 2);
    Ok(())
}
#[test]
fn malformed_enrichment_and_mismatched_word_cannot_modify_history() -> TestResult {
    let mut db = Database::in_memory()?;
    let (_, ids) = seed(&db)?;
    let committed = formal(&mut db, ids[0], ReviewRating::Good)?;
    let before = db.recent_logs(ids[0], 10)?;
    for n in [-1, 1_000_001] {
        let mut e = enrichment(ids[0], committed.log_id);
        e.reading_wrong_count = n;
        assert!(service::enrich(&mut db, vec![e]).is_err());
    }
    let e = enrichment(ids[0], committed.log_id);
    assert!(service::enrich(&mut db, vec![e.clone(), e]).is_err());
    assert!(service::enrich(&mut db, vec![enrichment(ids[1], committed.log_id)]).is_err());
    let mut e = enrichment(ids[0], committed.log_id);
    e.question_direction_raw_value = Some("unknown".into());
    assert!(service::enrich(&mut db, vec![e]).is_err());
    assert_eq!(db.recent_logs(ids[0], 10)?, before);
    Ok(())
}
#[test]
fn tempfile_complete_session_reopens_progress_mastery_favorite_and_original_enriched_logs(
) -> TestResult {
    let dir = tempfile::tempdir()?;
    let path = dir.path().join("session.sqlite3");
    let mut db = Database::open(&path)?;
    let (book, ids) = seed(&db)?;
    db.upsert_progress(&p(ids[1], LearningState::Review))?;
    previous_good(&db, ids[1])?;
    db.upsert_progress(&p(ids[3], LearningState::Review))?;
    let session = queue::start(
        &db,
        book,
        SessionMode::Mixed,
        NOW,
        &CalendarContext::fixed(28800)?,
        QueuePolicy {
            new_limit: 10,
            review_limit: 20,
            randomizes: false,
        },
        "Injected".into(),
    )?;
    assert_eq!(session.cards.len(), 4);
    let reinforced = formal(&mut db, ids[0], ReviewRating::Again)?;
    let automatic = formal(&mut db, ids[1], ReviewRating::Good)?;
    let kana = formal(&mut db, ids[2], ReviewRating::Hard)?;
    let spelling = formal(&mut db, ids[3], ReviewRating::Again)?;
    assert!(automatic.automatic_mastery);
    assert_eq!(automatic.progress.state, LearningState::Suspended);
    service::reinforcement_mastered(&mut db, ids[0], reinforced.progress, Timestamp(NOW.0 + 100))?;
    service::favorite(&mut db, ids[2], false, NOW)?;
    service::enrich(
        &mut db,
        vec![
            Enrichment {
                word_id: ids[2],
                log_id: kana.log_id,
                typed_answer: None,
                expected_answer: None,
                question_direction_raw_value: None,
                reading_wrong_count: 0,
                spelling_wrong_count: 0,
            },
            enrichment(ids[3], spelling.log_id),
        ],
    )?;
    assert_eq!(db.info()?.table_counts.review_logs, 5);
    let progress = ids
        .iter()
        .map(|id| db.fetch_progress(*id))
        .collect::<crate::db::Result<Vec<_>>>()?;
    let history = ids
        .iter()
        .map(|id| db.recent_logs(*id, 10))
        .collect::<crate::db::Result<Vec<_>>>()?;
    drop(db);
    let reopened = Database::open(&path)?;
    assert_eq!(reopened.info()?.schema_version, 2);
    assert_eq!(reopened.info()?.table_counts.review_logs, 5);
    for (i, id) in ids.iter().enumerate() {
        assert_eq!(reopened.fetch_progress(*id)?, progress[i]);
        assert_eq!(reopened.recent_logs(*id, 10)?, history[i]);
    }
    assert!(reopened.fetch_word(ids[2])?.ok_or("word")?.is_favorite);
    assert_eq!(history[0][0].rating, ReviewRating::Again);
    assert_eq!(history[1][0].rating, ReviewRating::Good);
    assert_eq!(history[3][0].spelling_wrong_count, 2);
    Ok(())
}
#[test]
fn real_manifest_tempfile_n5_session_is_small_and_returns_actual_lexical_cards() -> TestResult {
    let dir = tempfile::tempdir()?;
    let mut db = Database::open(&dir.path().join("builtin-session.sqlite3"))?;
    db.import_builtin(&crate::vocabulary::Manifest::embedded()?, NOW)?;
    let book = db
        .list_books()?
        .into_iter()
        .find(|b| b.canonical_key.as_deref() == Some("jlpt-n5"))
        .ok_or("N5")?;
    let session = queue::start(
        &db,
        book.id,
        SessionMode::NewWordsOnly,
        NOW,
        &CalendarContext::fixed(28800)?,
        QueuePolicy {
            new_limit: 3,
            review_limit: 20,
            randomizes: true,
        },
        "Injected".into(),
    )?;
    assert_eq!(session.cards.len(), 3);
    assert!(session.cards.iter().all(|c| c.word.word.jlpt_level == "N5"
        && !c.word.word.expression.is_empty()
        && !c.word.word.reading.is_empty()
        && c.expected_progress.is_none()));
    assert!(serde_json::to_vec(&session)?.len() < 20_000);
    assert_eq!(db.info()?.table_counts.vocabulary_words, 10609);
    assert_eq!(db.info()?.table_counts.learning_progress, 0);
    assert_eq!(db.info()?.table_counts.review_logs, 0);
    Ok(())
}
#[test]
fn native_timezone_provider_smoke_covers_sixty_days_without_mutating_host_timezone() -> TestResult {
    let now = now()?;
    let context = SystemLocalTimeContextProvider.context(now)?;
    assert!(!context.name.is_empty());
    assert!(context.calendar.add_days(now, 60)?.0 > now.0);
    assert!(context.calendar.day_end_exclusive(now)?.0 > now.0);
    Ok(())
}
