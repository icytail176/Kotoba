use super::{
    models::{Id, Timestamp},
    ui_reads::loanword,
    Database,
};
use crate::vocabulary::Manifest;
type TestResult = std::result::Result<(), Box<dyn std::error::Error>>;
fn seeded() -> std::result::Result<Database, Box<dyn std::error::Error>> {
    let mut db = Database::in_memory()?;
    db.import_builtin(&Manifest::embedded()?, Timestamp(123))?;
    Ok(db)
}
#[test]
fn product_books_exact_counts_and_dto_has_no_identity_or_learning_fields() -> TestResult {
    let db = seeded()?;
    let books = db.browse_books()?;
    assert_eq!(books.len(), 5);
    assert_eq!(
        books.iter().map(|b| b.word_count).collect::<Vec<_>>(),
        vec![802, 755, 1817, 3206, 4029]
    );
    let value = serde_json::to_value(&books[0])?;
    assert_eq!(value.as_object().ok_or("object")?.len(), 4);
    assert!(value.get("canonicalId").is_none());
    Ok(())
}
#[test]
fn product_pagination_stable_boundaries_and_global_browse() -> TestResult {
    let db = seeded()?;
    let books = db.browse_books()?;
    let book = books[0].id;
    let first = db.browse_words(Some(book), 50, 0)?;
    assert_eq!((first.total, first.items.len()), (802, 50));
    assert_eq!(
        first.items.iter().map(|w| w.id).collect::<Vec<_>>(),
        db.browse_words(Some(book), 50, 0)?
            .items
            .iter()
            .map(|w| w.id)
            .collect::<Vec<_>>()
    );
    assert_eq!(db.browse_words(Some(book), 50, 800)?.items.len(), 2);
    assert!(db.browse_words(Some(book), 50, 900)?.items.is_empty());
    let next = db.browse_words(Some(book), 50, 50)?;
    assert!(!next
        .items
        .iter()
        .any(|w| first.items.iter().any(|a| a.id == w.id)));
    assert_eq!(db.browse_words(None, 50, 0)?.total, 10609);
    assert!(db.browse_words(None, 0, 0).is_err());
    assert!(db.browse_words(None, 101, 0).is_err());
    Ok(())
}
#[test]
fn product_detail_by_local_id_and_safe_not_found() -> TestResult {
    let db = seeded()?;
    let first = db.browse_words(None, 1, 0)?;
    let word = &first.items[0];
    let detail = db.word_detail(word.id)?.ok_or("detail")?;
    assert_eq!(detail.word.expression, word.expression);
    assert_eq!(detail.word.book_id, word.book_id);
    assert!(!detail.part_of_speech.is_empty());
    assert!(detail
        .tags
        .iter()
        .all(|t| !t.starts_with("音调:") && !t.starts_with("原词性:")));
    assert!(db
        .word_detail(Id::parse("ffffffff-ffff-4fff-8fff-ffffffffffff")?)?
        .is_none());
    let value = serde_json::to_value(detail)?;
    for hidden in [
        "canonicalId",
        "canonicalKey",
        "createdAt",
        "isFavorite",
        "dueAt",
    ] {
        assert!(value.get(hidden).is_none());
    }
    Ok(())
}
#[test]
fn product_search_book_labels_paging_and_literal_wildcards() -> TestResult {
    let db = seeded()?;
    let result = db.browse_search("高校", 1, 0)?;
    assert_eq!(result.total, 2);
    assert_eq!(result.items.len(), 1);
    assert_eq!(result.items[0].book_name, "JLPT N5");
    let next = db.browse_search("高校", 1, 1)?;
    assert_ne!(result.items[0].id, next.items[0].id);
    assert!(db.browse_search("高校", 1, 2)?.items.is_empty());
    assert!(db.browse_search(" ", 50, 0)?.items.is_empty());
    let literal = db.browse_words(None, 1, 0)?.items[0].id;
    db.connection.execute(
        "UPDATE vocabulary_words SET japanese=?1 WHERE id=?2",
        rusqlite::params![r"literal%_\tail", literal],
    )?;
    for query in ["%", "_", r"\", r"%_\"] {
        let results = db.browse_search(query, 50, 0)?;
        assert!(results.total < 10609);
        assert!(results.items.iter().any(|word| word.id == literal));
    }
    assert!(db.browse_search(&"字".repeat(201), 50, 0).is_err());
    assert_eq!(db.browse_search("' OR 1=1 --", 50, 0)?.total, 0);
    assert!(db.browse_search("高中", 50, 0)?.total >= 2);
    assert!(db.browse_search("こうこう", 50, 0)?.total >= 2);
    assert!(db.browse_search("x", 101, 0).is_err());
    Ok(())
}
#[test]
fn product_loanword_policy_excludes_chinese_even_wasei_partial() -> TestResult {
    for code in ["chi", " ZH ", "zho", "sino-origin", "汉语"] {
        assert!(loanword(Some("source".into()), Some(code.into()), true, true).is_none());
    }
    assert!(loanword(Some("source".into()), None, false, false).is_none());
    assert!(loanword(Some(" ".into()), Some("eng".into()), true, false).is_none());
    assert_eq!(
        loanword(Some("source".into()), Some("eng".into()), true, true)
            .ok_or("source")?
            .language_name,
        Some("英语")
    );
    let db = seeded()?;
    let ids = db
        .connection
        .prepare("SELECT id FROM vocabulary_words WHERE loanword_source_language_code='chi'")?
        .query_map([], |r| r.get::<_, Id>(0))?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    assert_eq!(ids.len(), 2);
    for id in ids {
        assert!(db.word_detail(id)?.ok_or("detail")?.loanword.is_none());
        assert_eq!(
            db.fetch_word(id)?
                .ok_or("stored")?
                .loanword_source_language_code
                .as_deref(),
            Some("chi")
        );
    }
    Ok(())
}
