//! Mac import-quality diagnostics, with bounded IPC previews and a full CSV report.
use super::{csv::CsvPlan, models::Id, Database, Result};
use crate::lexical::{
    conjugation, pos_tokens,
    preview::{na_risk, needs_conjugation},
    unicode::trim,
};
use std::collections::{HashMap, HashSet};
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct QualityIssue {
    pub severity: &'static str,
    pub line_number: usize,
    pub expression: String,
    pub reason: String,
}
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct QualityReport {
    pub critical_count: usize,
    pub warning_count: usize,
    pub info_count: usize,
    pub conjugatable_missing_valid_data_count: usize,
    pub issues: Vec<QualityIssue>,
}
fn csv_field(s: &str) -> String {
    if s.contains([',', '"', '\n', '\r']) {
        format!("\"{}\"", s.replace('"', "\"\""))
    } else {
        s.into()
    }
}
impl QualityReport {
    pub fn csv(&self) -> String {
        let mut lines = vec!["severity,lineNumber,expression,reason".into()];
        for i in &self.issues {
            let severity = match i.severity {
                "critical" => "严重错误",
                "warning" => "警告",
                _ => "提示",
            };
            lines.push(
                [
                    severity.into(),
                    i.line_number.to_string(),
                    i.expression.clone(),
                    i.reason.clone(),
                ]
                .iter()
                .map(|s| csv_field(s))
                .collect::<Vec<_>>()
                .join(","),
            );
        }
        lines.join("\n")
    }
}
impl Database {
    pub fn csv_quality(&self, plan: &CsvPlan, target: Option<Id>) -> Result<QualityReport> {
        let mut existing: HashMap<(String, String), HashSet<Option<Id>>> = HashMap::new();
        let mut stmt = self
            .connection
            .prepare("SELECT japanese,kana,word_book_id FROM vocabulary_words")?;
        for row in stmt.query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, Option<Id>>(2)?,
            ))
        })? {
            let (e, r, b) = row?;
            existing.entry((e, r)).or_default().insert(b);
        }
        let mut issues: Vec<_> = plan
            .errors
            .iter()
            .map(|e| QualityIssue {
                severity: "critical",
                line_number: e.row,
                expression: String::new(),
                reason: e.reason.clone(),
            })
            .collect();
        let mut missing = 0;
        let known = [
            "名词",
            "名詞",
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
            "い形容词",
            "い形容詞",
            "な形容词",
            "な形容詞",
            "形容词",
            "形容詞",
            "副词",
            "副詞",
            "助词",
            "助詞",
            "感叹词",
            "感動詞",
            "连体词",
            "連体詞",
        ];
        for row in &plan.rows {
            let pos = row.part_of_speech.as_deref().unwrap_or_default();
            let tokens = pos_tokens(pos);
            let mut add = |severity, reason: String| {
                issues.push(QualityIssue {
                    severity,
                    line_number: row.row,
                    expression: row.expression.clone(),
                    reason,
                })
            };
            if trim(pos).is_empty() {
                add(
                    "warning",
                    "partOfSpeech 为空，筛选和活用判断会变弱。".into(),
                )
            } else if tokens.iter().any(|t| matches!(t.as_str(), "动词" | "動詞")) {
                add(
                    "warning",
                    "词性只有“动词”，无法可靠判断一段、五段、サ变或カ变。".into(),
                )
            } else if tokens
                .iter()
                .any(|t| matches!(t.as_str(), "形容词" | "形容詞"))
            {
                add(
                    "warning",
                    "词性只有“形容词”，无法可靠判断い形容词或な形容词。".into(),
                )
            } else if tokens.iter().any(|t| !known.contains(&t.as_str())) {
                add(
                    "warning",
                    format!(
                        "partOfSpeech 包含无法识别的词性，请确认：{}。",
                        tokens.join("/")
                    ),
                )
            }
            if row.expression == row.reading {
                add(
                    "info",
                    "expression 与 reading 完全相同，适合纯假名词，但请确认不是漏填汉字写法。"
                        .into(),
                )
            }
            if let Some(books) = existing.get(&(row.expression.clone(), row.reading.clone())) {
                if target.is_some() && books.contains(&target) {
                    add(
                        "warning",
                        "当前导入目标中已存在相同 expression + reading。".into(),
                    )
                }
                if books.iter().any(|b| *b != target) {
                    add(
                        "info",
                        "其他词书中存在同名单词，请确认是否需要合并。".into(),
                    )
                }
            }
            if needs_conjugation(&tokens)
                && conjugation::generate(&row.expression, &row.reading, pos).is_none()
            {
                missing += 1;
                add(
                    "warning",
                    "可活用词缺少明确活用类型，无法生成可信本地活用。".into(),
                )
            }
            if row
                .tags
                .as_ref()
                .is_some_and(|v| v.iter().any(|t| t.contains('；')))
            {
                add("warning", "tags 使用了中文分号，请改用英文分号 ;。".into())
            }
            if !row
                .reading
                .chars()
                .all(|c| matches!(c as u32,0x3041..=0x3096|0x30a1..=0x30f6|0x30fc))
            {
                add(
                    "warning",
                    "reading 中包含非假名字符，请确认假名读音。".into(),
                )
            }
            let example = row.example_japanese.as_deref().unwrap_or_default();
            if trim(example).is_empty() {
                add("info", "缺少日语例句。".into())
            } else if !example.contains(&row.expression) {
                add("info", "日语例句中未直接包含 expression。".into())
            }
            if trim(row.example_chinese.as_deref().unwrap_or_default()).is_empty() {
                add("info", "缺少中文例句翻译。".into())
            }
            if na_risk(&row.expression, &row.reading, &tokens) {
                add(
                    "warning",
                    format!(
                        "{} 以 い 结尾，但常见为な形容词，请确认词性。",
                        row.expression
                    ),
                )
            }
        }
        issues.sort_by_key(|i| {
            (
                match i.severity {
                    "critical" => 0,
                    "warning" => 1,
                    _ => 2,
                },
                i.line_number,
            )
        });
        Ok(QualityReport {
            critical_count: issues.iter().filter(|i| i.severity == "critical").count(),
            warning_count: issues.iter().filter(|i| i.severity == "warning").count(),
            info_count: issues.iter().filter(|i| i.severity == "info").count(),
            conjugatable_missing_valid_data_count: missing,
            issues,
        })
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn report_has_source_severities_line_numbers_and_escaped_csv() {
        let db = Database::in_memory().unwrap();
        let plan=super::super::csv::parse("expression,reading,meaningChinese,partOfSpeech,tags\n\"語,句\",kanji,词,动词,注意；标签\n猫,ねこ,猫,名词,\n空,,空,,\n");
        let report = db.csv_quality(&plan, None).unwrap();
        assert_eq!(report.critical_count, 1);
        assert_eq!(report.warning_count, 4);
        assert_eq!(report.info_count, 4);
        assert_eq!(report.conjugatable_missing_valid_data_count, 1);
        assert_eq!(report.issues[0].line_number, 4);
        let csv = report.csv();
        assert!(csv.starts_with("severity,lineNumber,expression,reason\n严重错误,4"));
        assert!(csv.contains("\"語,句\""));
    }
}
