//! Current Mac word-editor preview warnings and six local forms.
use super::{
    conjugation::{self, Conjugation},
    pos_tokens,
    unicode::trim,
};
#[derive(Debug, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EditorPreview {
    pub normalized_part_of_speech_tokens: Vec<String>,
    pub conjugation: Option<Conjugation>,
    pub is_conjugatable: bool,
    pub requires_manual_review: bool,
    pub warnings: Vec<String>,
}
pub fn needs_conjugation(tokens: &[String]) -> bool {
    let known = [
        "动词",
        "動詞",
        "一段动词",
        "一段動詞",
        "五段动词",
        "五段動詞",
        "サ变动词",
        "サ変動詞",
        "する动词",
        "する動詞",
        "カ变动词",
        "カ変動詞",
        "形容词",
        "形容詞",
        "い形容词",
        "い形容詞",
        "な形容词",
        "な形容詞",
    ];
    tokens.iter().any(|t| known.contains(&t.as_str()))
}
pub fn na_risk(expression: &str, reading: &str, tokens: &[String]) -> bool {
    tokens
        .iter()
        .any(|t| matches!(t.as_str(), "い形容词" | "い形容詞"))
        && ["きれい", "綺麗", "嫌い", "きらい", "有名", "ゆうめい"]
            .iter()
            .any(|s| *s == expression || *s == reading)
}
pub fn editor(expression: &str, reading: &str, pos: &str) -> EditorPreview {
    let tokens = pos_tokens(pos);
    let mut generated = conjugation::generate(expression, reading, pos);
    let is_conjugatable = needs_conjugation(&tokens);
    let requires_manual_review = is_conjugatable && generated.is_none();
    let mut warnings = Vec::new();
    if tokens.iter().any(|t| matches!(t.as_str(), "动词" | "動詞")) {
        warnings.push("词性只有“动词”，请标注为五段动词、一段动词、サ变动词或カ变动词。".into())
    }
    if tokens
        .iter()
        .any(|t| matches!(t.as_str(), "形容词" | "形容詞"))
    {
        warnings.push("词性只有“形容词”，请标注为い形容词或な形容词。".into())
    }
    if na_risk(trim(expression), trim(reading), &tokens) {
        warnings.push(format!(
            "{} 以 い 结尾，但常见为な形容词，请确认不要误标为い形容词。",
            trim(expression)
        ))
    }
    if requires_manual_review {
        warnings.push("当前输入无法生成可信本地活用，保存后需要人工检查。".into())
    }
    if tokens.is_empty() {
        warnings.push("词性为空，无法进行筛选或活用判断。".into())
    }
    if let Some(value) = &mut generated {
        value.forms.retain(|f| f.form_type != "dictionary");
        value.forms.truncate(6);
    }
    EditorPreview {
        normalized_part_of_speech_tokens: tokens,
        conjugation: generated,
        is_conjugatable,
        requires_manual_review,
        warnings,
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn conservative_preview_matches_source() {
        let p = editor("食べる", "たべる", "一段动词");
        assert_eq!(p.conjugation.unwrap().forms.len(), 6);
        assert!(!p.requires_manual_review);
        let p = editor("食べる", "たべる", "动词");
        assert!(p.requires_manual_review);
        assert_eq!(p.warnings.len(), 2);
        assert!(editor("綺麗", "きれい", "い形容词")
            .warnings
            .iter()
            .any(|w| w.contains("な形容词")));
        assert_eq!(editor("猫", "ねこ", "").warnings.len(), 1);
    }
}
