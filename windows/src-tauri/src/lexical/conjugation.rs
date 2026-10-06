//! Direct deterministic port of the current local Mac rule engine.
use super::{godan_map::GODAN, pos_tokens, unicode::trim};

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Form {
    pub form_type: &'static str,
    pub label: &'static str,
    pub surface: String,
    pub reading: String,
}
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Conjugation {
    pub conjugation_class: &'static str,
    pub forms: Vec<Form>,
}
const VERB_TYPES: [&str; 11] = [
    "polite",
    "negative",
    "past",
    "teForm",
    "conditional",
    "potential",
    "volitional",
    "imperative",
    "passive",
    "causative",
    "causativePassive",
];
fn label(kind: &str) -> &'static str {
    match kind {
        "dictionary" => "辞书形",
        "polite" => "ます形",
        "negative" => "否定形",
        "past" => "过去形",
        "teForm" => "て形",
        "connective" => "连接形",
        "conditional" => "条件形",
        "potential" => "可能形",
        "volitional" => "意志形",
        "imperative" => "命令形",
        "passive" => "被动形",
        "causative" => "使役形",
        "causativePassive" => "使役被动形",
        "adverbial" => "副词形",
        _ => "活用",
    }
}
fn form(kind: &'static str, expression: String, reading: String) -> Form {
    Form {
        form_type: kind,
        label: label(kind),
        surface: expression,
        reading,
    }
}
fn dictionary(e: &str, r: &str) -> Form {
    form("dictionary", e.into(), r.into())
}
fn suffix_forms(
    class: &'static str,
    e: &str,
    r: &str,
    es: &str,
    rs: &str,
    suffixes: &[(&'static str, &str, &str)],
) -> Conjugation {
    let mut forms = vec![dictionary(e, r)];
    forms.extend(
        suffixes
            .iter()
            .map(|(kind, a, b)| form(kind, format!("{es}{a}"), format!("{rs}{b}"))),
    );
    Conjugation {
        conjugation_class: class,
        forms,
    }
}
fn verb(
    class: &'static str,
    e: &str,
    r: &str,
    es: &str,
    rs: &str,
    suffixes: [&str; 11],
) -> Conjugation {
    let suffixes: Vec<_> = VERB_TYPES
        .iter()
        .zip(suffixes)
        .map(|(kind, s)| (*kind, s, s))
        .collect();
    suffix_forms(class, e, r, es, rs, &suffixes)
}
fn suru(e: &str, r: &str) -> Conjugation {
    verb(
        "suruVerb",
        e,
        r,
        e.strip_suffix("する").unwrap_or(e),
        r.strip_suffix("する").unwrap_or(r),
        [
            "します",
            "しない",
            "した",
            "して",
            "すれば",
            "できる",
            "しよう",
            "しろ",
            "される",
            "させる",
            "させられる",
        ],
    )
}
fn kuru(e: &str, r: &str) -> Option<Conjugation> {
    let (es, kanji) = e
        .strip_suffix("来る")
        .map(|s| (s, true))
        .or_else(|| e.strip_suffix("くる").map(|s| (s, false)))?;
    let rs = r.strip_suffix("くる")?;
    let kana = [
        "きます",
        "こない",
        "きた",
        "きて",
        "くれば",
        "こられる",
        "こよう",
        "こい",
        "こられる",
        "こさせる",
        "こさせられる",
    ];
    let surface = [
        "来ます",
        "来ない",
        "来た",
        "来て",
        "来れば",
        "来られる",
        "来よう",
        "来い",
        "来られる",
        "来させる",
        "来させられる",
    ];
    let suffixes: Vec<_> = VERB_TYPES
        .iter()
        .enumerate()
        .map(|(i, t)| (*t, if kanji { surface[i] } else { kana[i] }, kana[i]))
        .collect();
    Some(suffix_forms("kuruVerb", e, r, es, rs, &suffixes))
}
fn godan(e: &str, r: &str) -> Option<Conjugation> {
    let special = [
        "問う",
        "請う",
        "乞う",
        "いらっしゃる",
        "おっしゃる",
        "くださる",
        "なさる",
        "ござる",
    ];
    if special.contains(&e) || special.contains(&r) {
        return None;
    }
    let ending = e.chars().last()?;
    if !r.ends_with(ending) {
        return None;
    }
    let (_, suffixes) = GODAN.iter().find(|(c, _)| *c == ending)?;
    Some(verb(
        "godanVerb",
        e,
        r,
        e.strip_suffix(ending)?,
        r.strip_suffix(ending)?,
        *suffixes,
    ))
}
pub fn generate(expression: &str, reading: &str, pos: &str) -> Option<Conjugation> {
    let e = trim(expression);
    let r = trim(reading);
    if e.is_empty() || r.is_empty() {
        return None;
    }
    let tokens = pos_tokens(pos);
    let has = |values: &[&str]| tokens.iter().any(|t| values.contains(&t.as_str()));
    if e == "いい" && r == "いい" {
        return Some(suffix_forms(
            "iAdjective",
            e,
            r,
            "",
            "",
            &[
                ("polite", "いいです", "いいです"),
                ("negative", "よくない", "よくない"),
                ("past", "よかった", "よかった"),
                ("teForm", "よくて", "よくて"),
                ("conditional", "よければ", "よければ"),
                ("adverbial", "よく", "よく"),
            ],
        ));
    }
    if e == "来る" || e == "くる" || has(&["カ变动词", "カ変動詞"]) {
        return kuru(e, r);
    }
    if e == "行く" || e == "いく" {
        if r != "いく" {
            return None;
        }
        return Some(verb(
            "godanVerb",
            e,
            r,
            if e == "行く" { "行" } else { "い" },
            "い",
            [
                "きます",
                "かない",
                "った",
                "って",
                "けば",
                "ける",
                "こう",
                "け",
                "かれる",
                "かせる",
                "かせられる",
            ],
        ));
    }
    if e == "ある" && r == "ある" {
        return Some(suffix_forms(
            "godanVerb",
            e,
            r,
            "",
            "",
            &[
                ("polite", "あります", "あります"),
                ("negative", "ない", "ない"),
                ("past", "あった", "あった"),
                ("teForm", "あって", "あって"),
                ("conditional", "あれば", "あれば"),
                ("volitional", "あろう", "あろう"),
                ("imperative", "あれ", "あれ"),
            ],
        ));
    }
    if e == "する" || r == "する" {
        return Some(suru(e, r));
    }
    if has(&["一段动词", "一段動詞"]) {
        if [
            "帰る", "走る", "入る", "切る", "知る", "要る", "減る", "滑る", "喋る", "参る",
        ]
        .contains(&e)
        {
            return None;
        }
        return Some(verb(
            "ichidanVerb",
            e,
            r,
            e.strip_suffix('る')?,
            r.strip_suffix('る')?,
            [
                "ます",
                "ない",
                "た",
                "て",
                "れば",
                "られる",
                "よう",
                "ろ",
                "られる",
                "させる",
                "させられる",
            ],
        ));
    }
    if has(&["五段动词", "五段動詞"]) {
        return godan(e, r);
    }
    if has(&["サ变动词", "サ変動詞", "する动词", "する動詞"]) {
        return Some(suru(e, r));
    }
    if has(&["い形容词", "い形容詞"]) {
        return Some(suffix_forms(
            "iAdjective",
            e,
            r,
            e.strip_suffix('い')?,
            r.strip_suffix('い')?,
            &[
                ("polite", "いです", "いです"),
                ("negative", "くない", "くない"),
                ("past", "かった", "かった"),
                ("teForm", "くて", "くて"),
                ("conditional", "ければ", "ければ"),
                ("adverbial", "く", "く"),
            ],
        ));
    }
    if has(&["な形容词", "な形容詞"]) {
        return Some(suffix_forms(
            "naAdjective",
            e,
            r,
            e,
            r,
            &[
                ("polite", "です", "です"),
                ("negative", "ではない", "ではない"),
                ("past", "だった", "だった"),
                ("connective", "で", "で"),
                ("conditional", "なら", "なら"),
                ("adverbial", "に", "に"),
            ],
        ));
    }
    if has(&["名词", "名詞", "副词", "副詞"]) {
        return Some(Conjugation {
            conjugation_class: "none",
            forms: vec![dictionary(e, r)],
        });
    }
    None
}
