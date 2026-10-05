use super::*;
type TestResult = std::result::Result<(), Box<dyn std::error::Error>>;
#[test]
fn embedded_manifest_parses_version_and_exact_book_counts() -> TestResult {
    let m = Manifest::embedded()?;
    assert_eq!(
        (m.format_version, m.manifest_version, m.entry_count),
        (1, 1, 10609)
    );
    for (key, _, count) in COUNTS {
        assert_eq!(
            m.books
                .iter()
                .find(|b| b.canonical_key == key)
                .map(|b| b.entry_count),
            Some(count)
        );
    }
    assert_eq!(
        m.entries
            .iter()
            .filter(|e| e.loanword_source_term.is_some())
            .count(),
        836
    );
    assert_eq!(
        m.entries
            .iter()
            .filter(|e| e.loanword_source_language_code.as_deref() == Some("chi"))
            .count(),
        2
    );
    assert_eq!(
        m.entries
            .iter()
            .filter(|e| e.tags.iter().any(|t| t.starts_with("音调:")))
            .count(),
        10398
    );
    Ok(())
}
#[test]
fn permanent_uuid_v5_contract_vectors() -> TestResult {
    for (name, id) in [
        ("book:jlpt-n5", "b4dcfc10-7e03-51a2-8f64-67d692c6a5ee"),
        ("jlpt:n5:000001", "6871898e-46e5-50c3-bf24-db1af7b30c46"),
        ("jlpt:n4:000001", "465a5b4d-1a74-5b0a-b924-80a5cd2a193e"),
        ("jlpt:n1:004029", "74ee073b-38f3-5c4b-ba21-1279f7a659a2"),
    ] {
        assert_eq!(
            uuid::Uuid::new_v5(&NAMESPACE, name.as_bytes()).to_string(),
            id
        );
    }
    // RFC UUID v5 vector guards the generator independently of our namespace.
    assert_eq!(
        uuid::Uuid::new_v5(&uuid::Uuid::NAMESPACE_DNS, b"www.widgets.com").to_string(),
        "21f7f8de-8051-5b89-8680-0195ef798b6a"
    );
    Ok(())
}
#[test]
fn all_canonical_keys_and_ids_are_globally_unique() -> TestResult {
    let m = Manifest::embedded()?;
    let keys: HashSet<_> = m
        .entries
        .iter()
        .map(|e| &e.canonical_key)
        .chain(m.books.iter().map(|b| &b.canonical_key))
        .collect();
    let ids: HashSet<_> = m
        .entries
        .iter()
        .map(|e| &e.canonical_id)
        .chain(m.books.iter().map(|b| &b.canonical_id))
        .collect();
    assert_eq!(keys.len(), 10614);
    assert_eq!(ids.len(), 10614);
    Ok(())
}
#[test]
fn duplicate_lexical_entries_retain_distinct_canonical_identities() -> TestResult {
    let m = Manifest::embedded()?;
    let mut grouped: HashMap<_, Vec<_>> = HashMap::new();
    for e in &m.entries {
        grouped
            .entry((&e.expression, &e.reading))
            .or_default()
            .push(e);
    }
    let duplicates: Vec<_> = grouped.values().filter(|g| g.len() > 1).collect();
    assert_eq!(duplicates.len(), 10);
    for group in duplicates {
        assert_eq!(
            group
                .iter()
                .map(|e| &e.canonical_id)
                .collect::<HashSet<_>>()
                .len(),
            group.len()
        );
    }
    Ok(())
}
#[test]
fn invalid_version_namespace_uuid_and_reassignment_rejected() -> TestResult {
    let original = Manifest::embedded()?;
    let mut m = original.clone();
    m.format_version = 2;
    assert!(m.validate().is_err());
    let mut m = original.clone();
    m.namespace_uuid = uuid::Uuid::NAMESPACE_DNS.to_string();
    assert!(m.validate().is_err());
    let mut m = original.clone();
    m.entries[0].canonical_id = m.entries[1].canonical_id.clone();
    assert!(m.validate().is_err());
    let mut m = original.clone();
    m.entries[0].canonical_key.clear();
    assert!(m.validate().is_err());
    let mut m = original;
    m.entries[0].identity_anchor = "0".repeat(64);
    assert!(m.validate().is_err());
    Ok(())
}
#[test]
fn unknown_book_missing_required_field_and_counts_rejected() -> TestResult {
    let original = Manifest::embedded()?;
    let mut m = original.clone();
    m.entries[0].book_key = "unknown".into();
    assert!(m.validate().is_err());
    let mut m = original.clone();
    m.entries[0].reading.clear();
    assert!(m.validate().is_err());
    let mut m = original.clone();
    m.entry_count -= 1;
    assert!(m.validate().is_err());
    let mut value = serde_json::to_value(original)?;
    if let Some(object) = value["entries"][0].as_object_mut() {
        object.remove("expression");
    }
    assert!(Manifest::parse(&value.to_string()).is_err());
    Ok(())
}
#[test]
fn metadata_corrections_and_reorder_preserve_identity() -> TestResult {
    let mut m = Manifest::embedded()?;
    let before = m.identity_fingerprint()?;
    let hash = m.fingerprint()?;
    m.entries.reverse();
    assert_eq!(m.fingerprint()?, hash);
    assert_eq!(m.identity_fingerprint()?, before);
    m.entries[0].meaning_chinese.push_str(" correction");
    m.entries[0].reading.push('あ');
    m.manifest_version = 2;
    m.validate()?;
    assert_eq!(m.identity_fingerprint()?, before);
    assert_ne!(m.fingerprint()?, hash);
    Ok(())
}
#[test]
fn embedded_resource_needs_no_runtime_repository_path() -> TestResult {
    let m = Manifest::parse(EMBEDDED_MANIFEST)?;
    assert_eq!(m.entries.len(), 10609);
    assert!(!EMBEDDED_MANIFEST.contains("/Users/"));
    assert!(!EMBEDDED_MANIFEST.contains("C:\\Users\\"));
    // include_str! embeds bytes in the executable; no runtime std::fs read is used.
    Ok(())
}
