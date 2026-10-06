use super::*;
use serde_json::{json, Value};

fn gold() -> Value {
    serde_json::from_str(include_str!(
        "../../../tests/fixtures/mac-lexical-golden.json"
    ))
    .unwrap()
}
fn conjugation_json(e: &str, r: &str, pos: &str) -> Value {
    let mut value = serde_json::to_value(conjugation::generate(e, r, pos)).unwrap();
    if let Some(forms) = value.get_mut("forms").and_then(Value::as_array_mut) {
        for form in forms {
            form.as_object_mut().unwrap().remove("label");
        }
    }
    value
}
#[test]
fn full_vocabulary_matches_actual_mac_services() {
    let manifest = crate::vocabulary::Manifest::embedded().unwrap();
    let expected = gold();
    let rows = expected["vocabulary"].as_array().unwrap();
    assert_eq!(rows.len(), 10609);
    assert_eq!(rows.len(), manifest.entries.len());
    let mut coverage = 0;
    for (word, row) in manifest.entries.iter().zip(rows) {
        let actual = romaji(&word.reading);
        assert!(!actual.is_empty(), "{}", word.canonical_key);
        assert!(!actual.contains('\u{fffd}'));
        assert!(!actual.contains("''"));
        assert_eq!(
            json!(actual),
            row["romaji"],
            "romaji {}",
            word.canonical_key
        );
        let accent = pitch(&word.tags);
        coverage += usize::from(accent.is_some());
        assert_eq!(
            serde_json::to_value(accent).unwrap(),
            row["pitch"],
            "pitch {}",
            word.canonical_key
        );
        assert_eq!(
            conjugation_json(&word.expression, &word.reading, &word.part_of_speech),
            row["conjugation"],
            "conjugation {}",
            word.canonical_key
        );
    }
    assert_eq!(coverage, 10398);
}
#[test]
fn romaji_and_conjugation_edge_goldens() {
    let data = gold();
    for row in data["edges"].as_array().unwrap() {
        assert_eq!(
            json!(romaji(row["reading"].as_str().unwrap())),
            row["romaji"],
            "{row}"
        );
    }
    for row in data["conjugationEdges"].as_array().unwrap() {
        assert_eq!(
            conjugation_json(
                row["expression"].as_str().unwrap(),
                row["reading"].as_str().unwrap(),
                row["partOfSpeech"].as_str().unwrap()
            ),
            row["expected"],
            "{row}"
        );
    }
}
#[test]
fn pitch_missing_invalid_and_composite() {
    for tag in ["", "音调:", "音调:0", "音调:①、", "音调:①++②", "音调:①abc"] {
        assert!(pitch(&[tag.into()]).is_none());
    }
    assert!(pitch(&[]).is_none());
    assert_eq!(
        pitch(&["音调:①+①、③".into()]).unwrap(),
        Pitch {
            display_text: "[1+1, 3]".into(),
            accessibility_text: "音调型 1加1，或3".into()
        }
    );
    assert_eq!(pitch(&["音调:⓪③".into()]).unwrap().display_text, "[0/3]");
}
#[test]
fn normalization_preserves_japanese_voicing_and_folds_search() {
    assert_eq!(romaji("か\u{3099}"), "ga");
    assert_eq!(
        unicode::search_key("\u{200b}ＡＢＣ É Ō ｶﾞ\u{200b}"),
        "abc e o ガ"
    );
    assert_ne!(unicode::search_key("か"), unicode::search_key("が"));
    assert_eq!(pos_tokens(" 名词 / サ变动词 /名词/ "), ["名词", "サ变动词"]);
}
