use super::{calendar::*, models::*, scheduler, service::*};
use crate::db::{models::*, Database};
type TestResult = std::result::Result<(), Box<dyn std::error::Error>>;
fn utc() -> Result<CalendarContext> {
    CalendarContext::fixed(0)
}
fn progress(state: LearningState, days: i64) -> LearningProgress {
    LearningProgress {
        id: Id::new_local(),
        word_id: Id::new_local(),
        state,
        due_at: Timestamp(0),
        interval_days: days,
        review_count: 5,
        lapse_count: 1,
        last_reviewed_at: None,
        created_at: Timestamp(0),
        updated_at: Timestamp(0),
    }
}
fn seed(db: &Database) -> crate::db::Result<Id> {
    let id = Id::new_local();
    db.upsert_word(&VocabularyWord {
        id,
        japanese: "確認".into(),
        kana: "かくにん".into(),
        chinese_meaning: "确认".into(),
        part_of_speech: "名词".into(),
        jlpt_level: "N1".into(),
        example_japanese: String::new(),
        example_chinese: String::new(),
        tags: vec![],
        created_at: Timestamp(0),
        updated_at: Timestamp(0),
        is_archived: false,
        is_favorite: false,
        loanword_source_term: None,
        loanword_source_language_code: None,
        loanword_is_wasei: false,
        loanword_is_partial: false,
        word_book_id: None,
        canonical_id: None,
        canonical_key: None,
    })?;
    Ok(id)
}
fn rate(
    db: &mut Database,
    word: Id,
    rating: ReviewRating,
    now: Timestamp,
) -> Result<CommittedReview> {
    let request = FormalRatingRequest {
        word_id: word,
        expected_progress: db.fetch_progress(word)?,
        rating: FormalRating(rating),
        now,
    };
    apply_formal_rating_transaction(db, request, &utc()?)
}
fn la() -> std::result::Result<CalendarContext, Box<dyn std::error::Error>> {
    let data: serde_json::Value =
        serde_json::from_str(include_str!("../../../tests/fixtures/srs-parity.json"))?;
    let rules = &data["laRules"];
    let transitions = rules["transitions"]
        .as_array()
        .ok_or("transitions")?
        .iter()
        .map(|t| {
            Ok(OffsetTransition {
                at: Timestamp(t["at"].as_i64().ok_or("at")?),
                offset_seconds: i32::try_from(t["offset"].as_i64().ok_or("offset")?)?,
            })
        })
        .collect::<std::result::Result<Vec<_>, Box<dyn std::error::Error>>>()?;
    Ok(CalendarContext::new(
        Timestamp(rules["start"].as_i64().ok_or("start")?),
        Timestamp(rules["end"].as_i64().ok_or("end")?),
        i32::try_from(rules["initial"].as_i64().ok_or("initial")?)?,
        transitions,
    )?)
}
#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct Vector {
    name: String,
    state: String,
    interval: i64,
    rating: String,
    previous: Option<String>,
    archived: bool,
    zone: String,
    now: i64,
    next_state: String,
    next_interval: i64,
    due: i64,
    reviews: i64,
    lapses: i64,
    did_lapse: bool,
    automatic: bool,
}
#[test]
fn mac_generated_golden_transitions_rounding_mastery_and_calendar_vectors() -> TestResult {
    let data: serde_json::Value =
        serde_json::from_str(include_str!("../../../tests/fixtures/srs-parity.json"))?;
    let vectors: Vec<Vector> = serde_json::from_value(data["vectors"].clone())?;
    assert!(vectors.len() >= 50);
    for v in vectors {
        let calendar = match v.zone.as_str() {
            "UTC" => utc()?,
            "Asia/Shanghai" => CalendarContext::fixed(28_800)?,
            "America/Los_Angeles" => la()?,
            _ => return Err("zone".into()),
        };
        let p = progress(parse_state(&v.state)?, v.interval);
        let result = scheduler::schedule(
            &ProgressSnapshot::from(&p),
            FormalRating::parse(&v.rating)?,
            Timestamp(v.now),
            v.previous
                .as_deref()
                .map(FormalRating::parse)
                .transpose()?
                .map(|r| r.0),
            v.archived,
            &calendar,
        )?;
        assert_eq!(
            result,
            Schedule {
                state: parse_state(&v.next_state)?,
                interval_days: v.next_interval,
                due_at: Timestamp(v.due),
                review_count: v.reviews,
                lapse_count: v.lapses,
                did_lapse: v.did_lapse,
                automatic_mastery: v.automatic
            },
            "{}",
            v.name
        );
    }
    Ok(())
}
#[test]
fn invalid_enums_negative_progress_and_counter_overflow_are_typed() -> TestResult {
    assert!(matches!(
        parse_state("unknown"),
        Err(SrsError::InvalidState)
    ));
    assert!(matches!(
        FormalRating::parse("mastered"),
        Err(SrsError::InvalidRating)
    ));
    for field in 0..3 {
        let mut p = progress(LearningState::Review, 10);
        match field {
            0 => p.interval_days = -1,
            1 => p.review_count = -1,
            _ => p.lapse_count = -1,
        }
        assert!(matches!(
            scheduler::schedule(
                &ProgressSnapshot::from(&p),
                FormalRating(ReviewRating::Good),
                Timestamp(0),
                None,
                false,
                &utc()?
            ),
            Err(SrsError::InvalidProgress)
        ));
    }
    let mut p = progress(LearningState::Review, i64::MAX);
    assert_eq!(
        scheduler::schedule(
            &ProgressSnapshot::from(&p),
            FormalRating(ReviewRating::Hard),
            Timestamp(0),
            None,
            false,
            &utc()?
        )?
        .interval_days,
        60
    );
    p.review_count = i64::MAX;
    assert!(matches!(
        scheduler::schedule(
            &ProgressSnapshot::from(&p),
            FormalRating(ReviewRating::Good),
            Timestamp(0),
            None,
            false,
            &utc()?
        ),
        Err(SrsError::CounterOverflow)
    ));
    p.review_count = 0;
    p.lapse_count = i64::MAX;
    assert!(matches!(
        scheduler::schedule(
            &ProgressSnapshot::from(&p),
            FormalRating(ReviewRating::Again),
            Timestamp(0),
            None,
            false,
            &utc()?
        ),
        Err(SrsError::CounterOverflow)
    ));
    Ok(())
}
#[test]
fn timestamp_and_context_overflow_never_wrap_or_fall_back_to_utc() -> TestResult {
    let p = progress(LearningState::New, 0);
    for rating in [ReviewRating::Again, ReviewRating::Hard, ReviewRating::Good] {
        assert!(scheduler::schedule(
            &ProgressSnapshot::from(&p),
            FormalRating(rating),
            Timestamp(i64::MAX - 1),
            None,
            false,
            &utc()?
        )
        .is_err());
    }
    assert!(matches!(
        CalendarContext::fixed(86_401),
        Err(SrsError::InvalidCalendar)
    ));
    assert!(matches!(
        CalendarContext::new(Timestamp(10), Timestamp(0), 0, vec![]),
        Err(SrsError::InvalidCalendar)
    ));
    assert!(matches!(
        la()?.add_days(Timestamp(0), 1),
        Err(SrsError::CalendarCoverage)
    ));
    let leap = utc()?.add_days(Timestamp(-1), 1)?;
    assert_eq!(leap.0, DAY_MICROS - 1);
    Ok(())
}
#[test]
fn formal_ratings_persist_and_reopen_without_fake_spelling_or_duplicate_log() -> TestResult {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("rating.sqlite3");
    let mut db = Database::open(&path)?;
    let word = seed(&db)?;
    let first = rate(&mut db, word, ReviewRating::Good, Timestamp(123_456))?;
    assert_eq!(first.progress.review_count, 1);
    assert_eq!(first.progress.interval_days, 2);
    let second = rate(&mut db, word, ReviewRating::Hard, first.progress.due_at)?;
    assert_eq!(second.progress.interval_days, 3);
    assert_eq!(second.log.previous_state, LearningState::Review);
    let logs = db.recent_logs(word, 10)?;
    assert_eq!(logs.len(), 2);
    for log in logs {
        assert!(log.typed_answer.is_none());
        assert!(log.expected_answer.is_none());
        assert!(log.question_direction_raw_value.is_none());
        assert_eq!(
            (
                log.reading_wrong_count,
                log.spelling_wrong_count,
                log.repeated_wrong_count
            ),
            (0, 0, 0)
        );
    }
    drop(db);
    let db = Database::open(&path)?;
    assert_eq!(db.fetch_progress(word)?, Some(second.progress));
    assert_eq!(recent_review_logs(&db, word, 10)?.len(), 2);
    assert_eq!(db.info()?.schema_version, 2);
    Ok(())
}
#[test]
fn automatic_mastery_real_transaction_reopens_and_good_log_stays_good() -> TestResult {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("mastery.sqlite3");
    let mut db = Database::open(&path)?;
    let word = seed(&db)?;
    let mut now = Timestamp(0);
    for days in [2, 4, 8, 16, 32, 60] {
        let committed = rate(&mut db, word, ReviewRating::Good, now)?;
        assert!(!committed.automatic_mastery);
        assert_eq!(committed.progress.interval_days, days);
        now = committed.progress.due_at;
    }
    let committed = rate(&mut db, word, ReviewRating::Good, now)?;
    assert!(committed.automatic_mastery);
    assert_eq!(committed.progress.state, LearningState::Suspended);
    assert_eq!(committed.progress.interval_days, 0);
    assert_eq!(committed.progress.due_at, now);
    assert_eq!(committed.progress.review_count, 7);
    assert_eq!(committed.log.rating, ReviewRating::Good);
    assert_eq!(committed.log.previous_interval_days, 60);
    assert_eq!(committed.log.next_interval_days, 0);
    assert_eq!(committed.log.previous_state, LearningState::Review);
    assert_eq!(committed.log.next_state, LearningState::Suspended);
    assert_eq!(committed.log.scheduled_due_at, now);
    assert_eq!(db.recent_logs(word, 100)?.len(), 7);
    drop(db);
    let db = Database::open(&path)?;
    assert_eq!(db.fetch_progress(word)?, Some(committed.progress));
    assert_eq!(db.recent_logs(word, 100)?.len(), 7);
    Ok(())
}
#[test]
fn hard_breaks_qualification_until_second_subsequent_good() -> TestResult {
    let mut db = Database::in_memory()?;
    let word = seed(&db)?;
    let mut p = progress(LearningState::Review, 32);
    p.word_id = word;
    db.upsert_progress(&p)?;
    let cap = rate(&mut db, word, ReviewRating::Good, Timestamp(0))?;
    assert!(!cap.automatic_mastery);
    let hard = rate(&mut db, word, ReviewRating::Hard, cap.progress.due_at)?;
    assert!(!hard.automatic_mastery);
    let good = rate(&mut db, word, ReviewRating::Good, hard.progress.due_at)?;
    assert!(!good.automatic_mastery);
    assert!(rate(&mut db, word, ReviewRating::Good, good.progress.due_at)?.automatic_mastery);
    assert_eq!(db.recent_logs(word, 10)?.len(), 4);
    Ok(())
}
#[test]
fn again_and_relearning_break_mastery_and_increment_lapses() -> TestResult {
    let mut db = Database::in_memory()?;
    let word = seed(&db)?;
    let mut p = progress(LearningState::Review, 32);
    p.word_id = word;
    db.upsert_progress(&p)?;
    let cap = rate(&mut db, word, ReviewRating::Good, Timestamp(0))?;
    let again = rate(&mut db, word, ReviewRating::Again, cap.progress.due_at)?;
    assert_eq!(again.progress.state, LearningState::Relearning);
    assert_eq!(again.progress.lapse_count, 2);
    assert_eq!(again.log.rating, ReviewRating::Again);
    assert_eq!(
        db.recent_logs(word, 1)?[0].error_types,
        vec![ReviewErrorType::Meaning]
    );
    let repeated = rate(&mut db, word, ReviewRating::Again, again.progress.due_at)?;
    assert_eq!(repeated.progress.lapse_count, 3);
    let good = rate(&mut db, word, ReviewRating::Good, repeated.progress.due_at)?;
    assert!(!good.automatic_mastery);
    assert_eq!(good.progress.interval_days, 2);
    Ok(())
}
#[test]
fn manual_mastery_from_all_active_states_is_one_easy_log() -> TestResult {
    let mut db = Database::in_memory()?;
    for state in [
        LearningState::New,
        LearningState::Learning,
        LearningState::Review,
        LearningState::Relearning,
    ] {
        let word = seed(&db)?;
        let mut p = progress(state, 10);
        p.word_id = word;
        db.upsert_progress(&p)?;
        let committed = rate(&mut db, word, ReviewRating::Easy, Timestamp(123))?;
        assert_eq!(committed.progress.state, LearningState::Suspended);
        assert_eq!(committed.progress.interval_days, 0);
        assert_eq!(committed.progress.due_at, Timestamp(123));
        assert_eq!(committed.progress.review_count, 6);
        assert_eq!(committed.progress.lapse_count, 1);
        assert_eq!(committed.log.rating, ReviewRating::Easy);
        assert_eq!(db.recent_logs(word, 10)?.len(), 1);
    }
    Ok(())
}
#[test]
fn rollback_checkpoints_restore_progress_log_word_and_lazy_creation() -> TestResult {
    for stage in [Checkpoint::AfterProgress, Checkpoint::AfterLog] {
        for existing in [false, true] {
            let mut db = Database::in_memory()?;
            let word = seed(&db)?;
            if existing {
                rate(&mut db, word, ReviewRating::Good, Timestamp(123))?;
            }
            let before = db.fetch_progress(word)?;
            let logs = db.recent_logs(word, 10)?;
            let old_word = db.fetch_word(word)?;
            let request = FormalRatingRequest {
                word_id: word,
                expected_progress: before.clone(),
                rating: FormalRating(ReviewRating::Good),
                now: Timestamp(456),
            };
            let result = apply(&mut db, request, &utc()?, |point| {
                if std::mem::discriminant(&point) == std::mem::discriminant(&stage) {
                    Err(SrsError::InvalidProgress)
                } else {
                    Ok(())
                }
            });
            assert!(result.is_err());
            assert_eq!(db.fetch_progress(word)?, before);
            assert_eq!(db.recent_logs(word, 10)?, logs);
            assert_eq!(db.fetch_word(word)?, old_word);
        }
    }
    Ok(())
}
#[test]
fn actual_sql_failure_at_insert_and_after_insert_rolls_back_everything() -> TestResult {
    for sql in ["CREATE TEMP TRIGGER reject_progress BEFORE UPDATE ON learning_progress BEGIN SELECT RAISE(ABORT,'test progress failure'); END", "CREATE TEMP TRIGGER reject_log BEFORE INSERT ON review_logs BEGIN SELECT RAISE(ABORT,'test insert failure'); END", "CREATE TEMP TRIGGER reject_word BEFORE UPDATE ON vocabulary_words BEGIN SELECT RAISE(ABORT,'test word failure'); END"] {
        let mut db=Database::in_memory()?;let word=seed(&db)?;rate(&mut db,word,ReviewRating::Good,Timestamp(0))?;
        let before=db.fetch_progress(word)?;let logs=db.recent_logs(word,10)?;
        db.connection.execute_batch(sql)?;assert!(rate(&mut db,word,ReviewRating::Good,Timestamp(1)).is_err());
        assert_eq!(db.fetch_progress(word)?,before);assert_eq!(db.recent_logs(word,10)?,logs);
    }
    Ok(())
}
#[test]
fn duplicate_submission_is_detected_and_retry_after_failure_commits_once() -> TestResult {
    let mut db = Database::in_memory()?;
    let word = seed(&db)?;
    let make_request = || FormalRatingRequest {
        word_id: word,
        expected_progress: None,
        rating: FormalRating(ReviewRating::Good),
        now: Timestamp(0),
    };
    assert!(apply(&mut db, make_request(), &utc()?, |_| Err(
        SrsError::InvalidProgress
    ))
    .is_err());
    apply_formal_rating_transaction(&mut db, make_request(), &utc()?)?;
    assert!(matches!(
        apply_formal_rating_transaction(&mut db, make_request(), &utc()?),
        Err(SrsError::StaleProgress)
    ));
    assert_eq!(db.recent_logs(word, 10)?.len(), 1);
    let snapshot = db.fetch_progress(word)?;
    let make_request = || FormalRatingRequest {
        word_id: word,
        expected_progress: snapshot.clone(),
        rating: FormalRating(ReviewRating::Hard),
        now: Timestamp(1),
    };
    apply_formal_rating_transaction(&mut db, make_request(), &utc()?)?;
    assert!(matches!(
        apply_formal_rating_transaction(&mut db, make_request(), &utc()?),
        Err(SrsError::StaleProgress)
    ));
    assert_eq!(db.recent_logs(word, 10)?.len(), 2);
    Ok(())
}
#[test]
fn missing_archived_and_suspended_formal_reviews_are_rejected() -> TestResult {
    let mut db = Database::in_memory()?;
    assert!(matches!(
        rate(&mut db, Id::new_local(), ReviewRating::Good, Timestamp(0)),
        Err(SrsError::MissingWord)
    ));
    let word = seed(&db)?;
    let mut item = db.fetch_word(word)?.ok_or("word")?;
    item.is_archived = true;
    db.upsert_word(&item)?;
    assert!(matches!(
        rate(&mut db, word, ReviewRating::Good, Timestamp(0)),
        Err(SrsError::ArchivedWord)
    ));
    assert!(db.fetch_progress(word)?.is_none());
    item.is_archived = false;
    db.upsert_word(&item)?;
    rate(&mut db, word, ReviewRating::Easy, Timestamp(0))?;
    assert!(matches!(
        rate(&mut db, word, ReviewRating::Good, Timestamp(1)),
        Err(SrsError::SuspendedWord)
    ));
    assert_eq!(db.recent_logs(word, 10)?.len(), 1);
    Ok(())
}
#[test]
fn enriched_formal_history_uses_index_and_deterministic_id_tie_break() -> TestResult {
    let mut db = Database::in_memory()?;
    let word = seed(&db)?;
    let first = rate(&mut db, word, ReviewRating::Good, Timestamp(0))?;
    db.connection.execute(
        "UPDATE review_logs SET typed_answer='spell',spelling_wrong_count=2 WHERE word_id=?1",
        [word],
    )?;
    assert_eq!(
        fetch_latest_formal_log_for_word(&db, word)?
            .ok_or("log")?
            .id,
        first.log.id
    );
    let second = rate(&mut db, word, ReviewRating::Hard, Timestamp(0))?;
    let expected = if first.log.id.to_string() < second.log.id.to_string() {
        first.log.id
    } else {
        second.log.id
    };
    assert_eq!(
        fetch_latest_formal_log_for_word(&db, word)?
            .ok_or("log")?
            .id,
        expected
    );
    let logs = recent_review_logs(&db, word, 10)?;
    assert_eq!(logs[0].id, expected);
    assert_eq!(logs.len(), 2);
    for limit in [0, 101] {
        assert!(matches!(
            recent_review_logs(&db, word, limit),
            Err(SrsError::InvalidLimit)
        ));
    }
    let plan:String=db.connection.query_row("EXPLAIN QUERY PLAN SELECT id FROM review_logs WHERE word_id=?1 ORDER BY reviewed_at DESC,id LIMIT 1",[word],|r|r.get(3))?;
    assert!(plan.contains("logs_by_word_date"), "{plan}");
    Ok(())
}
#[test]
fn due_queries_match_mac_local_review_day_and_exact_minute_states() -> TestResult {
    let db = Database::in_memory()?;
    let now = Timestamp(12 * 60 * MINUTE_MICROS);
    let cases = [
        (LearningState::New, 0, false),
        (LearningState::Suspended, 0, false),
        (LearningState::Learning, now.0, true),
        (LearningState::Relearning, now.0 + 1, false),
        (LearningState::Review, DAY_MICROS - 1, true),
        (LearningState::Review, DAY_MICROS, false),
    ];
    let mut expected = Vec::new();
    for (state, due, included) in cases {
        let word = seed(&db)?;
        let mut p = progress(state, 2);
        p.word_id = word;
        p.due_at = Timestamp(due);
        if included {
            expected.push(p.id);
        }
        db.upsert_progress(&p)?;
    }
    let actual = due_progress(&db, now, &utc()?)?;
    assert_eq!(actual.len(), expected.len());
    assert!(actual.iter().all(|p| expected.contains(&p.id)));
    db.connection
        .execute("UPDATE vocabulary_words SET is_archived=1", [])?;
    assert!(due_progress(&db, now, &utc()?)?.is_empty());
    // Spring day ends at 07:00Z, fall at 08:00Z; independent of host timezone.
    assert_eq!(
        la()?.day_end_exclusive(Timestamp(1_772_996_400_000_000))?,
        Timestamp(1_773_039_600_000_000)
    );
    assert_eq!(
        la()?.day_end_exclusive(Timestamp(1_793_563_200_000_000))?,
        Timestamp(1_793_606_400_000_000)
    );
    Ok(())
}
#[test]
fn eligible_new_includes_missing_progress_filters_archive_and_other_states() -> TestResult {
    let db = Database::in_memory()?;
    let fresh = seed(&db)?;
    let new = seed(&db)?;
    let mut p = progress(LearningState::New, 0);
    p.word_id = new;
    db.upsert_progress(&p)?;
    for state in [
        LearningState::Learning,
        LearningState::Relearning,
        LearningState::Review,
        LearningState::Suspended,
    ] {
        let word = seed(&db)?;
        let mut p = progress(state, 0);
        p.word_id = word;
        db.upsert_progress(&p)?;
    }
    let archived = seed(&db)?;
    db.connection.execute(
        "UPDATE vocabulary_words SET is_archived=1 WHERE id=?1",
        [archived],
    )?;
    let rows = eligible_new_words(&db, None, 50, 0)?;
    assert_eq!(rows.len(), 2);
    assert!(rows.contains(&fresh));
    assert!(rows.contains(&new));
    assert_eq!(eligible_new_words(&db, None, 1, 0)?.len(), 1);
    assert!(eligible_new_words(&db, None, 50, 2)?.is_empty());
    assert!(eligible_new_words(&db, Some(Id::new_local()), 50, 0)?.is_empty());
    assert!(eligible_new_words(&db, None, 0, 0).is_err());
    Ok(())
}
#[test]
fn presentation_groups_are_independent_from_persisted_states() -> TestResult {
    assert_eq!(
        LearningStatusPresentation::from_state(None),
        LearningStatusPresentation::Unlearned
    );
    assert_eq!(
        LearningStatusPresentation::from_state(Some(LearningState::New)),
        LearningStatusPresentation::Unlearned
    );
    for state in [
        LearningState::Learning,
        LearningState::Relearning,
        LearningState::Review,
    ] {
        assert_eq!(
            LearningStatusPresentation::from_state(Some(state)),
            LearningStatusPresentation::Reviewing
        );
    }
    assert_eq!(
        LearningStatusPresentation::from_state(Some(LearningState::Suspended)),
        LearningStatusPresentation::Mastered
    );
    Ok(())
}

#[test]
fn commit_failure_returns_no_result_and_rolls_back_progress_and_log() -> TestResult {
    let mut db = Database::in_memory()?;
    let word = seed(&db)?;
    rate(&mut db, word, ReviewRating::Good, Timestamp(0))?;
    let before = db.fetch_progress(word)?;
    let logs = db.recent_logs(word, 10)?;
    db.connection.execute_batch("CREATE TEMP TRIGGER bad_deferred_fk AFTER UPDATE ON vocabulary_words BEGIN UPDATE learning_progress SET word_id='ffffffff-ffff-4fff-8fff-ffffffffffff' WHERE word_id=NEW.id; END; PRAGMA defer_foreign_keys=ON;")?;
    assert!(rate(&mut db, word, ReviewRating::Good, Timestamp(1)).is_err());
    assert_eq!(db.fetch_progress(word)?, before);
    assert_eq!(db.recent_logs(word, 10)?, logs);
    assert_eq!(db.info()?.table_counts.learning_progress, 1);
    Ok(())
}
#[test]
fn automatic_mastery_failure_retries_same_snapshot_with_one_good_log() -> TestResult {
    let mut db = Database::in_memory()?;
    let word = seed(&db)?;
    let mut p = progress(LearningState::Review, 32);
    p.word_id = word;
    db.upsert_progress(&p)?;
    let cap = rate(&mut db, word, ReviewRating::Good, Timestamp(0))?;
    let request = || FormalRatingRequest {
        word_id: word,
        expected_progress: Some(cap.progress.clone()),
        rating: FormalRating(ReviewRating::Good),
        now: cap.progress.due_at,
    };
    db.connection.execute_batch("CREATE TEMP TRIGGER reject_mastery BEFORE INSERT ON review_logs BEGIN SELECT RAISE(ABORT,'test mastery failure'); END")?;
    assert!(apply_formal_rating_transaction(&mut db, request(), &utc()?).is_err());
    assert_eq!(db.fetch_progress(word)?, Some(cap.progress.clone()));
    assert_eq!(db.recent_logs(word, 10)?.len(), 1);
    db.connection.execute_batch("DROP TRIGGER reject_mastery")?;
    let committed = apply_formal_rating_transaction(&mut db, request(), &utc()?)?;
    assert!(committed.automatic_mastery);
    assert_eq!(committed.log.rating, ReviewRating::Good);
    assert_eq!(db.recent_logs(word, 10)?.len(), 2);
    Ok(())
}

#[test]
fn product_detail_reads_actual_progress_without_exposing_raw_state() -> TestResult {
    let mut db = Database::in_memory()?;
    db.import_builtin(&crate::vocabulary::Manifest::embedded()?, Timestamp(0))?;
    let word = db.browse_words(None, 1, 0)?.items[0].id;
    assert_eq!(
        db.word_detail(word)?.ok_or("detail")?.learning_status,
        LearningStatusPresentation::Unlearned
    );
    for state in [
        LearningState::New,
        LearningState::Learning,
        LearningState::Relearning,
        LearningState::Review,
        LearningState::Suspended,
    ] {
        let existing = db.fetch_progress(word)?;
        let mut p = existing.unwrap_or_else(|| progress(state, 0));
        p.word_id = word;
        p.state = state;
        db.upsert_progress(&p)?;
        let detail = db.word_detail(word)?.ok_or("detail")?;
        assert_eq!(
            detail.learning_status,
            LearningStatusPresentation::from_state(Some(state))
        );
        let json = serde_json::to_value(detail)?;
        assert!(json.get("state").is_none());
        assert!(json.get("dueAt").is_none());
        assert!(json.get("learningStatus").is_some());
    }
    Ok(())
}
