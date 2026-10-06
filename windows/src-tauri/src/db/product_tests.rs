use super::{
    backup::*,
    csv::*,
    models::*,
    product_reads::*,
    tests::{book, id, log, progress, word},
    Database,
};
use crate::srs::{
    calendar::{CalendarContext, OffsetTransition},
    models::DAY_MICROS,
};
type TestResult = std::result::Result<(), Box<dyn std::error::Error>>;
fn fixture() -> super::Result<Database> {
    let db = Database::in_memory()?;
    db.upsert_book(&book().unwrap())?;
    for n in 2..9 {
        let mut w = word(n).unwrap();
        w.japanese = format!("詞{n}");
        w.kana = if n == 2 {
            "しんよう".into()
        } else {
            format!("かな{n}")
        };
        w.is_favorite = n == 2;
        w.is_archived = n == 8;
        w.loanword_source_term = Some("Coffee".into());
        w.loanword_source_language_code = Some("eng".into());
        w.part_of_speech = "名词/サ变动词".into();
        w.tags = vec!["复合".into(), "音调:①+①、③".into()];
        db.upsert_word(&w)?;
        if n != 2 {
            let mut p = progress(n + 100, w.id).unwrap();
            p.state = match n {
                3 => LearningState::New,
                4 => LearningState::Learning,
                5 => LearningState::Relearning,
                6 => LearningState::Review,
                _ => LearningState::Suspended,
            };
            p.due_at = Timestamp((8 - n as i64) * DAY_MICROS);
            p.last_reviewed_at = Some(Timestamp(n as i64));
            p.lapse_count = if n >= 6 { 2 } else { 1 };
            db.upsert_progress(&p)?;
        }
    }
    Ok(db)
}
fn query() -> WordQuery {
    WordQuery {
        book_id: None,
        search: String::new(),
        status: WordFilter::All,
        favorites_only: false,
        jlpt: None,
        part_of_speech: None,
        tag: None,
        sort: WordSort::DefaultOrder,
        limit: 100,
        offset: 0,
    }
}
#[test]
fn all_six_filters_and_combinations_are_sqlite_backed() -> TestResult {
    let db = fixture()?;
    for (status, count) in [
        (WordFilter::All, 6),
        (WordFilter::New, 2),
        (WordFilter::Review, 3),
        (WordFilter::Mastered, 1),
        (WordFilter::Favorite, 1),
        (WordFilter::Difficult, 2),
    ] {
        let mut q = query();
        q.status = status;
        assert_eq!(db.product_words(q)?.total, count);
    }
    let mut q = query();
    q.status = WordFilter::Mastered;
    q.favorites_only = true;
    assert_eq!(db.product_words(q)?.total, 0);
    let mut q = query();
    q.search = "SHIN'YO".into();
    q.part_of_speech = Some("サ变动词".into());
    q.tag = Some("复合".into());
    q.jlpt = Some("N5".into());
    assert_eq!(db.product_words(q)?.items[0].id, id(2)?);
    let mut q = query();
    q.search = "ＣＯＦＦＥＥ".into();
    assert_eq!(db.product_words(q)?.total, 6);
    let mut q = query();
    q.search = "%_\\' OR 1=1".into();
    assert_eq!(db.product_words(q)?.total, 0);
    let mut q = query();
    q.part_of_speech = Some("动词".into());
    assert_eq!(db.product_words(q)?.total, 0);
    Ok(())
}
#[test]
fn sorting_pagination_and_boundaries() -> TestResult {
    let db = fixture()?;
    let mut q = query();
    q.sort = WordSort::RecentlyStudied;
    assert_eq!(db.product_words(q)?.items[0].id, id(7)?);
    let mut q = query();
    q.sort = WordSort::NextDue;
    assert_eq!(db.product_words(q)?.items[0].id, id(6)?);
    let mut q = query();
    q.sort = WordSort::LapseCount;
    assert_eq!(db.product_words(q)?.items[0].id, id(6)?);
    let mut q = query();
    q.limit = 2;
    q.offset = 4;
    assert_eq!(db.product_words(q)?.items.len(), 2);
    let mut q = query();
    q.limit = 2;
    q.offset = 6;
    assert!(db.product_words(q)?.items.is_empty());
    let mut q = query();
    q.limit = 101;
    assert!(db.product_words(q).is_err());
    let books = db.product_books()?;
    assert_eq!(
        (
            books[0].word_count,
            books[0].unlearned,
            books[0].reviewing,
            books[0].mastered
        ),
        (6, 2, 3, 1)
    );
    Ok(())
}
#[test]
fn detail_derives_lexical_data_without_mutating_metadata() -> TestResult {
    let db = fixture()?;
    let before = db.fetch_word(id(2)?)?;
    let detail = db.product_detail(id(2)?)?.ok_or("detail")?;
    assert_eq!(detail.word.romaji, "shin'yō");
    assert_eq!(detail.pitch.ok_or("pitch")?.display_text, "[1+1, 3]");
    assert!(detail.conjugation.is_some());
    assert!(detail.loanword.is_some());
    assert_eq!(db.fetch_word(id(2)?)?, before);
    assert!(db.product_detail(id(8)?)?.is_none());
    Ok(())
}
#[test]
fn history_orders_pages_and_uses_internal_transitions() -> TestResult {
    let db = fixture()?;
    let mut old = log(30, id(6)?, 100)?;
    old.previous_state = LearningState::Review;
    old.previous_interval_days = 10;
    old.next_state = LearningState::Relearning;
    db.insert_log(&old)?;
    let mut next = old.clone();
    next.id = id(31)?;
    next.reviewed_at = Timestamp(200);
    next.next_state = LearningState::Suspended;
    next.rating = ReviewRating::Easy;
    db.insert_log(&next)?;
    let first = db.word_history(id(6)?, 1, 0)?;
    assert_eq!(first.total, 2);
    assert_eq!(first.items[0].transition, "10天 → 已熟练");
    let second = db.word_history(id(6)?, 1, 1)?;
    assert_eq!(second.items[0].transition, "复习 → 重新学习");
    assert_eq!(second.items[0].log.spelling_wrong_count, 2);
    assert!(db.word_history(id(6)?, 0, 0).is_err());
    Ok(())
}
#[test]
fn reset_word_exact_semantics_and_rollback() -> TestResult {
    let db = fixture()?;
    let id = id(6)?;
    let before = db.fetch_word(id)?.ok_or("word")?;
    let p = db.fetch_progress(id)?.ok_or("progress")?;
    let l = log(30, id, 100)?;
    db.insert_log(&l)?;
    assert!(db.reset_word(id, false, Timestamp(999)).is_err());
    db.connection.execute_batch("CREATE TRIGGER fail_reset BEFORE DELETE ON review_logs BEGIN SELECT RAISE(ABORT,'injected'); END;")?;
    assert!(db.reset_word(id, true, Timestamp(999)).is_err());
    assert_eq!(db.fetch_progress(id)?, Some(p.clone()));
    assert_eq!(db.recent_logs(id, 10)?, vec![l]);
    db.connection.execute_batch("DROP TRIGGER fail_reset")?;
    db.reset_word(id, true, Timestamp(999))?;
    let after = db.fetch_progress(id)?.ok_or("progress")?;
    assert_eq!(after.id, p.id);
    assert_eq!(after.created_at, p.created_at);
    assert_eq!(
        (
            after.state,
            after.due_at,
            after.interval_days,
            after.review_count,
            after.lapse_count,
            after.last_reviewed_at
        ),
        (LearningState::New, Timestamp(999), 0, 0, 0, None)
    );
    assert_eq!(db.fetch_word(id)?, Some(before));
    assert!(db.recent_logs(id, 10)?.is_empty());
    Ok(())
}
#[test]
fn book_reset_preserves_logs_and_ignores_archived() -> TestResult {
    let db = fixture()?;
    let l = log(30, id(6)?, 100)?;
    db.insert_log(&l)?;
    let archived = db.fetch_progress(id(8)?)?;
    db.reset_book(id(1)?, true, Timestamp(1234))?;
    assert_eq!(db.fetch_progress(id(8)?)?, archived);
    assert_eq!(db.recent_logs(id(6)?, 10)?, vec![l]);
    assert!(db.fetch_progress(id(2)?)?.is_some());
    assert_eq!(
        db.fetch_word(id(6)?)?.ok_or("word")?.updated_at,
        Timestamp(1234)
    );
    Ok(())
}
#[test]
fn forecast_local_days_minute_states_and_overdue() -> TestResult {
    let db = fixture()?;
    let cal = CalendarContext::fixed(9 * 3600)?;
    let now = Timestamp(DAY_MICROS * 4);
    let days = db.forecast(now, &cal, None)?;
    assert_eq!(days.len(), 7);
    assert_eq!(days[0].count, 3);
    assert_eq!(days.iter().map(|d| d.count).sum::<u32>(), 3);
    assert_eq!(
        days[0].day,
        Timestamp(4 * DAY_MICROS - 9 * 3600 * 1_000_000)
    );
    Ok(())
}
#[test]
fn forecast_dst_buckets_use_civil_day_boundaries() -> TestResult {
    let db = fixture()?;
    let cal = CalendarContext::new(
        Timestamp(-5 * DAY_MICROS),
        Timestamp(15 * DAY_MICROS),
        -8 * 3600,
        vec![OffsetTransition {
            at: Timestamp(10 * 3600 * 1_000_000),
            offset_seconds: -7 * 3600,
        }],
    )?;
    let now = Timestamp(12 * 3600 * 1_000_000);
    let days = db.forecast(now, &cal, None)?;
    assert_eq!(days[1].day.0 - days[0].day.0, 23 * 3600 * 1_000_000);
    Ok(())
}
#[test]
fn statistics_empty_seven_thirty_and_local_time() -> TestResult {
    let db = fixture()?;
    let cal = CalendarContext::fixed(9 * 3600)?;
    for days in [7, 30] {
        let stats = db.statistics(Timestamp(40 * DAY_MICROS), &cal, "Asia/Tokyo".into(), days)?;
        assert_eq!(stats.daily_activity.len(), days as usize);
        assert_eq!(stats.period_formal_review_count, 0);
        assert_eq!(stats.current_streak_days, 0);
        assert_eq!(stats.spelling_eligible, 0);
    }
    assert!(db.statistics(Timestamp(0), &cal, "UTC".into(), 8).is_err());
    Ok(())
}
#[test]
fn statistics_current_mac_mastery_spelling_streak_and_lapse_contract() -> TestResult {
    let db = fixture()?;
    let cal = CalendarContext::fixed(9 * 3600)?;
    let now = Timestamp(40 * DAY_MICROS);
    for (n, offset, rating, next, previous, direction) in [
        (
            30,
            -1,
            ReviewRating::Again,
            LearningState::Relearning,
            LearningState::Review,
            Some("expressionToReading"),
        ),
        (
            31,
            0,
            ReviewRating::Good,
            LearningState::Review,
            LearningState::New,
            None,
        ),
        (
            32,
            0,
            ReviewRating::Good,
            LearningState::Suspended,
            LearningState::Review,
            Some("meaningToExpression"),
        ),
        (
            33,
            0,
            ReviewRating::Easy,
            LearningState::Suspended,
            LearningState::Review,
            None,
        ),
        (
            34,
            1,
            ReviewRating::Hard,
            LearningState::Review,
            LearningState::Review,
            None,
        ),
    ] {
        let mut l = log(n, id(6)?, now.0 + offset * DAY_MICROS)?;
        l.rating = rating;
        l.next_state = next;
        l.previous_state = previous;
        l.question_direction_raw_value = direction.map(str::to_owned);
        l.spelling_wrong_count = 0;
        l.reading_wrong_count = 1;
        db.insert_log(&l)?;
    }
    let stats = db.statistics(now, &cal, "Asia/Tokyo".into(), 7)?;
    assert_eq!(
        (
            stats.today_new_word_count,
            stats.today_review_count,
            stats.total_review_count,
            stats.period_formal_review_count
        ),
        (1, 2, 5, 4)
    );
    assert_eq!(stats.current_streak_days, 2);
    assert_eq!(stats.period_newly_learned_word_count, 1);
    assert_eq!(
        (
            stats.period_manual_mastery_count,
            stats.period_automatic_mastery_count
        ),
        (1, 1)
    );
    assert_eq!(stats.rating_distribution, [1, 0, 2, 1]);
    assert_eq!((stats.spelling_passed, stats.spelling_eligible), (1, 2));
    assert_eq!(stats.top_lapsed_words[0].lapse_count, 1);
    assert_eq!(stats.daily_activity.last().ok_or("daily")?.total_count, 3);
    let old = db.statistics(
        Timestamp(now.0 + 3 * DAY_MICROS),
        &cal,
        "Asia/Tokyo".into(),
        30,
    )?;
    assert_eq!(old.current_streak_days, 0);
    Ok(())
}
#[test]
fn csv_roundtrip_unicode_quotes_newlines_and_optional_values() -> TestResult {
    let db = fixture()?;
    let mut w = db.fetch_word(id(2)?)?.ok_or("word")?;
    w.japanese = "日,本\"語".into();
    w.chinese_meaning = "中文\n换行".into();
    w.tags = vec!["标签".into(), "空格".into()];
    db.upsert_word(&w)?;
    let csv = db.csv_export(id(1)?)?;
    let parsed = parse(&csv);
    assert!(parsed.errors.is_empty());
    assert_eq!(parsed.rows.len(), 7);
    let row = parsed
        .rows
        .iter()
        .find(|r| r.expression == w.japanese)
        .ok_or("row")?;
    assert_eq!(row.meaning_chinese, w.chinese_meaning);
    assert_eq!(row.tags.as_ref(), Some(&w.tags));
    assert_eq!(
        parse("\u{feff}expression,reading,meaningChinese\r\n日本語,にほんご,日语\r\n")
            .rows
            .len(),
        1
    );
    Ok(())
}
#[test]
fn csv_validation_line_numbers_headers_duplicates_and_enums() {
    for csv in [
        "expression,reading\n語,ご",
        "expression,reading,meaningChinese,expression\n語,ご,词,語",
        "expression,reading,meaningChinese\n\"語,ご,词",
    ] {
        assert!(!parse(csv).errors.is_empty());
        assert!(parse(csv).rows.is_empty());
    }
    let plan=parse("expression,reading,meaningChinese,jlptLevel\n語,ご,词,N5\n語,ご,重复,N5\n本,ほん,书,n5\n空,,空,N3\n");
    assert_eq!(plan.rows.len(), 1);
    assert_eq!(
        plan.errors.iter().map(|e| e.row).collect::<Vec<_>>(),
        [3, 4, 5]
    );
}
#[test]
fn csv_duplicate_update_preserves_identity_progress_and_omitted_optionals() -> TestResult {
    let db = fixture()?;
    let w = db.fetch_word(id(6)?)?.ok_or("word")?;
    let p = db.fetch_progress(w.id)?;
    let plan = parse(&format!(
        "expression,reading,meaningChinese\n{},{},新释义\n",
        w.japanese, w.kana
    ));
    let target = ImportTarget {
        book_id: Some(id(1)?),
        new_book_name: None,
    };
    let skipped = db.csv_import(
        &plan,
        target.clone(),
        DuplicatePolicy::Skip,
        true,
        Timestamp(123),
    )?;
    assert_eq!(skipped.skipped, 1);
    let summary = db.csv_import(&plan, target, DuplicatePolicy::Update, true, Timestamp(124))?;
    assert_eq!(summary.updated, 1);
    let after = db.fetch_word(w.id)?.ok_or("word")?;
    assert_eq!(after.chinese_meaning, "新释义");
    assert_eq!(after.tags, w.tags);
    assert_eq!(after.loanword_source_term, w.loanword_source_term);
    assert_eq!(after.canonical_id, w.canonical_id);
    assert_eq!(db.fetch_progress(w.id)?, p);
    Ok(())
}
#[test]
fn csv_new_book_partial_explicit_errors_and_transaction_rollback() -> TestResult {
    let db = fixture()?;
    let plan = parse(
        "expression,reading,meaningChinese\n日本語,にほんご,日语\n空,,空\n英語,えいご,英语\n",
    );
    let target = ImportTarget {
        book_id: None,
        new_book_name: Some("导入".into()),
    };
    let before = db.info()?.table_counts.word_books;
    db.connection.execute_batch("CREATE TRIGGER fail_import BEFORE INSERT ON vocabulary_words WHEN new.japanese='英語' BEGIN SELECT RAISE(ABORT,'injected'); END;")?;
    assert!(db
        .csv_import(
            &plan,
            target.clone(),
            DuplicatePolicy::Skip,
            true,
            Timestamp(100)
        )
        .is_err());
    assert_eq!(db.info()?.table_counts.word_books, before);
    db.connection.execute_batch("DROP TRIGGER fail_import")?;
    let summary = db.csv_import(&plan, target, DuplicatePolicy::Skip, true, Timestamp(100))?;
    assert_eq!((summary.imported, summary.errors), (2, 1));
    Ok(())
}
#[test]
fn windows_backup_roundtrip_preflight_and_restore_modes() -> TestResult {
    let db = fixture()?;
    db.insert_log(&log(30, id(6)?, 100)?)?;
    let backup = db.backup_export(Timestamp(123))?;
    let json = serde_json::to_vec(&backup)?;
    let backup = Backup::parse(&json)?;
    let other = Database::in_memory()?;
    let summary = other.backup_restore(&backup, RestorePolicy::Merge, true)?;
    assert_eq!(
        summary.inserted as i64,
        other.info()?.table_counts.word_books
            + other.info()?.table_counts.vocabulary_words
            + other.info()?.table_counts.learning_progress
            + other.info()?.table_counts.review_logs
    );
    assert_eq!(
        serde_json::to_value(other.backup_export(Timestamp(123))?)?,
        serde_json::to_value(&backup)?
    );
    assert_eq!(
        other
            .backup_restore(&backup, RestorePolicy::SkipExisting, true)?
            .inserted,
        0
    );
    let mut changed = backup.clone();
    changed.words[0].chinese_meaning = "更改".into();
    changed.words[0].updated_at = Timestamp(backup.words[0].updated_at.0 + 1);
    assert_eq!(
        other
            .backup_restore(&changed, RestorePolicy::Merge, true)?
            .updated,
        1
    );
    assert!(
        other
            .backup_restore(&backup, RestorePolicy::Overwrite, true)?
            .updated
            > 0
    );
    Ok(())
}
#[test]
fn backup_rejects_future_orphans_duplicate_identity_and_rolls_back() -> TestResult {
    let db = fixture()?;
    let backup = db.backup_export(Timestamp(123))?;
    let before = serde_json::to_value(&backup)?;
    for kind in 0..5 {
        let mut bad = backup.clone();
        match kind {
            0 => bad.format_version = 99,
            1 => bad.words[0].word_book_id = Some(id(999)?),
            2 => bad.words.push(bad.words[0].clone()),
            3 => bad.progress[0].word_id = id(998)?,
            _ => bad.words[0].canonical_id = Some(id(997)?),
        }
        assert!(db
            .backup_restore(&bad, RestorePolicy::Overwrite, true)
            .is_err());
        assert_eq!(
            serde_json::to_value(db.backup_export(Timestamp(123))?)?,
            before
        );
    }
    db.connection.execute_batch("CREATE TRIGGER fail_restore BEFORE UPDATE ON vocabulary_words BEGIN SELECT RAISE(ABORT,'injected'); END;")?;
    let mut changed = backup.clone();
    changed.books[0].name = "changed".into();
    assert!(db
        .backup_restore(&changed, RestorePolicy::Overwrite, true)
        .is_err());
    assert_eq!(
        serde_json::to_value(db.backup_export(Timestamp(123))?)?,
        before
    );
    assert!(Backup::parse(br#"{"schemaVersion":3}"#).is_err());
    Ok(())
}
#[test]
fn backup_remaps_actual_canonical_ids_to_fresh_install_without_duplicate_words() -> TestResult {
    let manifest = crate::vocabulary::Manifest::embedded()?;
    let mut source = Database::in_memory()?;
    source.import_builtin(&manifest, Timestamp(1))?;
    let source_word = source.browse_words(None, 1, 0)?.items[0].id;
    let mut w = source.fetch_word(source_word)?.ok_or("word")?;
    w.is_favorite = true;
    w.updated_at = Timestamp(999);
    source.upsert_word(&w)?;
    source.upsert_progress(&progress(30000, source_word)?)?;
    source.insert_log(&log(30001, source_word, 100)?)?;
    let backup = source.backup_export(Timestamp(1000))?;
    let mut destination = Database::in_memory()?;
    destination.import_builtin(&manifest, Timestamp(2))?;
    let destination_word = destination.browse_words(None, 1, 0)?.items[0].id;
    assert_ne!(source_word, destination_word);
    destination.backup_restore(&backup, RestorePolicy::Merge, true)?;
    assert_eq!(destination.info()?.table_counts.vocabulary_words, 10609);
    assert!(
        destination
            .fetch_word(destination_word)?
            .ok_or("word")?
            .is_favorite
    );
    assert_eq!(
        destination
            .fetch_progress(destination_word)?
            .ok_or("progress")?
            .word_id,
        destination_word
    );
    assert_eq!(destination.recent_logs(destination_word, 10)?.len(), 1);
    assert!(destination.fetch_word(source_word)?.is_none());
    Ok(())
}

#[test]
fn statistics_dst_local_grouping_and_range_boundaries() -> TestResult {
    let db = fixture()?;
    let hour = 3600 * 1_000_000;
    let cal = CalendarContext::new(
        Timestamp(-40 * DAY_MICROS),
        Timestamp(40 * DAY_MICROS),
        -8 * 3600,
        vec![OffsetTransition {
            at: Timestamp(10 * hour),
            offset_seconds: -7 * 3600,
        }],
    )?;
    for (n, time) in [
        (40, 7 * hour),
        (41, 8 * hour),
        (42, 30 * hour),
        (43, 31 * hour),
    ] {
        db.insert_log(&log(n, id(6)?, time)?)?;
    }
    let result = db.statistics(Timestamp(32 * hour), &cal, "Test/DST".into(), 7)?;
    let daily = &result.daily_activity;
    assert_eq!(daily[daily.len() - 3].total_count, 1);
    assert_eq!(daily[daily.len() - 2].total_count, 2);
    assert_eq!(daily[daily.len() - 1].total_count, 1);
    assert_eq!(
        daily[daily.len() - 1].day.0 - daily[daily.len() - 2].day.0,
        23 * hour
    );
    assert_eq!(result.period_formal_review_count, 4);
    Ok(())
}
#[test]
fn canonical_csv_and_editor_preserve_identity_hidden_tags_and_learning() -> TestResult {
    let mut db = Database::in_memory()?;
    db.import_builtin(&crate::vocabulary::Manifest::embedded()?, Timestamp(1))?;
    let wid = db.browse_words(None, 1, 0)?.items[0].id;
    let mut w = db.fetch_word(wid)?.ok_or("word")?;
    w.is_favorite = true;
    db.upsert_word(&w)?;
    let p = progress(30000, wid)?;
    db.upsert_progress(&p)?;
    let l = log(30001, wid, 100)?;
    db.insert_log(&l)?;
    let detail = db.product_detail(wid)?.ok_or("detail")?;
    assert_eq!(detail.editing_tags, w.tags);
    let plan = parse(&format!(
        "expression,reading,meaningChinese\n{},{},更新释义\n",
        w.japanese, w.kana
    ));
    db.csv_import(
        &plan,
        ImportTarget {
            book_id: w.word_book_id,
            new_book_name: None,
        },
        DuplicatePolicy::Update,
        true,
        Timestamp(10),
    )?;
    let after = db.fetch_word(wid)?.ok_or("word")?;
    assert!(after.canonical_id.is_some());
    assert_eq!(after.canonical_id, w.canonical_id);
    assert_eq!(after.tags, w.tags);
    assert_eq!(after.is_favorite, w.is_favorite);
    db.edit_word(
        super::product_mutations::WordEdit {
            id: Some(wid),
            book_id: w.word_book_id.ok_or("book")?,
            expression: w.japanese.clone(),
            reading: w.kana.clone(),
            meaning_chinese: "编辑释义".into(),
            part_of_speech: w.part_of_speech.clone(),
            jlpt_level: w.jlpt_level.clone(),
            example_japanese: w.example_japanese.clone(),
            example_chinese: w.example_chinese.clone(),
            tags: detail.editing_tags,
            is_favorite: true,
        },
        Timestamp(11),
    )?;
    let edited = db.fetch_word(wid)?.ok_or("word")?;
    assert_eq!(edited.canonical_id, w.canonical_id);
    assert_eq!(edited.tags, w.tags);
    assert_eq!(db.fetch_progress(wid)?, Some(p));
    assert_eq!(db.recent_logs(wid, 10)?, vec![l]);
    Ok(())
}
#[test]
fn backup_json_unknown_enums_and_future_database_schema_fail_before_writes() -> TestResult {
    let db = fixture()?;
    let backup = db.backup_export(Timestamp(123))?;
    let original = serde_json::to_value(&backup)?;
    for (key, value) in [("state", "future"), ("state", "reviewX")] {
        let mut bad = original.clone();
        bad["progress"][0][key] = serde_json::Value::String(value.into());
        assert!(Backup::parse(&serde_json::to_vec(&bad)?).is_err());
    }
    let mut bad = original.clone();
    bad["databaseSchema"] = serde_json::json!(99);
    assert!(Backup::parse(&serde_json::to_vec(&bad)?).is_err());
    assert_eq!(
        serde_json::to_value(db.backup_export(Timestamp(123))?)?,
        original
    );
    Ok(())
}
