//! Mac-compatible UTF-8 lexical CSV. Parse and preview before any mutation.
use super::{models::*, product_mutations::WordEdit, Database, DatabaseError, Result};
use crate::lexical::{pos_tokens, unicode::trim};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
const HEADERS: [&str; 8] = [
    "expression",
    "reading",
    "meaningChinese",
    "partOfSpeech",
    "exampleJapanese",
    "exampleChinese",
    "jlptLevel",
    "tags",
];
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CsvError {
    pub row: usize,
    pub reason: String,
}
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CsvRow {
    pub row: usize,
    pub expression: String,
    pub reading: String,
    pub meaning_chinese: String,
    pub part_of_speech: Option<String>,
    pub example_japanese: Option<String>,
    pub example_chinese: Option<String>,
    pub jlpt_level: Option<String>,
    pub tags: Option<Vec<String>>,
}
#[derive(Debug, Clone)]
pub struct CsvPlan {
    pub rows: Vec<CsvRow>,
    pub errors: Vec<CsvError>,
}
#[derive(Debug, Deserialize, Clone, Copy)]
#[serde(rename_all = "camelCase")]
pub enum DuplicatePolicy {
    Skip,
    Update,
}
#[derive(Debug, Serialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct ImportSummary {
    pub imported: u32,
    pub updated: u32,
    pub skipped: u32,
    pub errors: u32,
}
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ImportTarget {
    pub book_id: Option<Id>,
    pub new_book_name: Option<String>,
}
fn err(row: usize, reason: impl Into<String>) -> CsvError {
    CsvError {
        row,
        reason: reason.into(),
    }
}
fn records(text: &str) -> std::result::Result<Vec<(usize, Vec<String>)>, CsvError> {
    let mut records = Vec::new();
    let mut fields = Vec::new();
    let mut field = String::new();
    let mut quoted = false;
    let mut chars = text.chars().peekable();
    let mut line = 1;
    let mut first = 1;
    while let Some(c) = chars.next() {
        match c {
            '"' if quoted => {
                if chars.peek() == Some(&'"') {
                    chars.next();
                    field.push('"');
                } else {
                    quoted = false;
                }
            }
            '"' if field.is_empty() => quoted = true,
            ',' if !quoted => fields.push(std::mem::take(&mut field)),
            '\r' | '\n' => {
                if c == '\r' && chars.peek() == Some(&'\n') {
                    chars.next();
                }
                line += 1;
                if quoted {
                    field.push('\n');
                } else {
                    fields.push(std::mem::take(&mut field));
                    if fields.iter().any(|s| !trim(s).is_empty()) {
                        records.push((first, std::mem::take(&mut fields)));
                    } else {
                        fields.clear();
                    }
                    first = line;
                }
            }
            _ => field.push(c),
        }
    }
    if quoted {
        return Err(err(first, "引号未闭合。"));
    }
    fields.push(field);
    if fields.iter().any(|s| !trim(s).is_empty()) {
        records.push((first, fields));
    }
    Ok(records)
}
pub fn parse(text: &str) -> CsvPlan {
    let fail = |error| CsvPlan {
        rows: vec![],
        errors: vec![error],
    };
    let mut records = match records(text) {
        Ok(r) => r,
        Err(e) => return fail(e),
    };
    if records.is_empty() {
        return fail(err(1, "CSV 文件为空。"));
    }
    let (line, mut header) = records.remove(0);
    if let Some(first) = header.first_mut() {
        *first = first.trim_start_matches('\u{feff}').into();
    }
    let header: Vec<_> = header.iter().map(|s| trim(s)).collect();
    let mut names = HashSet::new();
    if header.iter().any(|h| !names.insert(*h)) {
        return fail(err(line, "CSV 表头重复。"));
    }
    for required in &HEADERS[..3] {
        if !header.contains(required) {
            return fail(err(line, format!("缺少必需表头：{required}")));
        }
    }
    let columns: HashMap<_, _> = header.iter().enumerate().map(|(i, h)| (*h, i)).collect();
    let mut seen = HashMap::new();
    let mut plan = CsvPlan {
        rows: vec![],
        errors: vec![],
    };
    for (line, values) in records {
        if values.len() > header.len() {
            plan.errors.push(err(line, "字段数多于表头。"));
            continue;
        }
        let value = |key: &str| {
            columns
                .get(key)
                .map(|i| trim(values.get(*i).map(String::as_str).unwrap_or_default()).to_owned())
        };
        let expression = value("expression").unwrap_or_default();
        let reading = value("reading").unwrap_or_default();
        let meaning_chinese = value("meaningChinese").unwrap_or_default();
        if [&expression, &reading, &meaning_chinese]
            .iter()
            .any(|s| s.is_empty())
        {
            plan.errors
                .push(err(line, "单词、读音、中文释义不能为空。"));
            continue;
        }
        let jlpt_level = value("jlptLevel");
        if jlpt_level
            .as_deref()
            .is_some_and(|s| !s.is_empty() && !matches!(s, "N1" | "N2" | "N3" | "N4" | "N5"))
        {
            plan.errors
                .push(err(line, "JLPT 等级必须为 N1–N5 或空值。"));
            continue;
        }
        if let Some(previous) = seen.get(&(expression.clone(), reading.clone())) {
            plan.errors.push(err(
                line,
                format!("与文件第 {previous} 行的单词和读音重复。"),
            ));
            continue;
        }
        seen.insert((expression.clone(), reading.clone()), line);
        let tags = value("tags").map(|s| {
            let mut result = Vec::new();
            for t in s.split(';').map(trim).filter(|t| !t.is_empty()) {
                if !result.iter().any(|v| v == t) {
                    result.push(t.to_owned())
                }
            }
            result
        });
        plan.rows.push(CsvRow {
            row: line,
            expression,
            reading,
            meaning_chinese,
            part_of_speech: value("partOfSpeech").map(|s| pos_tokens(&s).join("/")),
            example_japanese: value("exampleJapanese"),
            example_chinese: value("exampleChinese"),
            jlpt_level,
            tags,
        });
    }
    plan
}
fn escape(s: &str) -> String {
    if s.contains([',', '"', '\n', '\r']) {
        format!("\"{}\"", s.replace('"', "\"\""))
    } else {
        s.into()
    }
}
impl Database {
    pub fn csv_export(&self, book: Id) -> Result<String> {
        if self.fetch_book(book)?.is_none() {
            return Err(DatabaseError::InvalidData("book missing"));
        }
        let mut words = self.words_by_book(book)?;
        words.sort_by(|a, b| {
            a.japanese
                .cmp(&b.japanese)
                .then(a.kana.cmp(&b.kana))
                .then(a.id.to_string().cmp(&b.id.to_string()))
        });
        let mut output = format!("{}\n", HEADERS.join(","));
        for w in words {
            let values = [
                w.japanese,
                w.kana,
                w.chinese_meaning,
                w.part_of_speech,
                w.example_japanese,
                w.example_chinese,
                w.jlpt_level,
                w.tags.join(";"),
            ];
            output.push_str(
                &values
                    .iter()
                    .map(|s| escape(s))
                    .collect::<Vec<_>>()
                    .join(","),
            );
            output.push('\n');
        }
        Ok(output)
    }
    pub fn csv_duplicate_count(&self, plan: &CsvPlan, target: &ImportTarget) -> Result<u32> {
        let Some(book) = target.book_id else {
            return Ok(0);
        };
        if self.fetch_book(book)?.is_none() {
            return Err(DatabaseError::InvalidData("book missing"));
        }
        let existing: HashSet<_> = self
            .words_by_book(book)?
            .into_iter()
            .map(|w| (w.japanese, w.kana))
            .collect();
        Ok(plan
            .rows
            .iter()
            .filter(|r| existing.contains(&(r.expression.clone(), r.reading.clone())))
            .count() as u32)
    }
    pub fn csv_import(
        &self,
        plan: &CsvPlan,
        target: ImportTarget,
        policy: DuplicatePolicy,
        confirmed: bool,
        now: Timestamp,
    ) -> Result<ImportSummary> {
        if !confirmed || plan.rows.is_empty() {
            return Err(DatabaseError::InvalidData("confirmation required"));
        }
        if target.book_id.is_some() == target.new_book_name.is_some() {
            return Err(DatabaseError::InvalidData("choose one import target"));
        }
        self.product_transaction(|db| {
            let book = match target.book_id {
                Some(id) => {
                    if db.fetch_book(id)?.is_none() {
                        return Err(DatabaseError::InvalidData("book missing"));
                    }
                    id
                }
                None => db.edit_book(
                    None,
                    target.new_book_name.as_deref().unwrap_or_default(),
                    "CSV 导入",
                    now,
                )?,
            };
            let mut existing: HashMap<_, _> = db
                .words_by_book(book)?
                .into_iter()
                .map(|w| ((w.japanese.clone(), w.kana.clone()), w))
                .collect();
            let mut summary = ImportSummary {
                errors: plan.errors.len() as u32,
                ..ImportSummary::default()
            };
            for row in &plan.rows {
                let key = (row.expression.clone(), row.reading.clone());
                if let Some(word) = existing.get_mut(&key) {
                    match policy {
                        DuplicatePolicy::Skip => summary.skipped += 1,
                        DuplicatePolicy::Update => {
                            word.chinese_meaning = row.meaning_chinese.clone();
                            if let Some(v) = &row.part_of_speech {
                                word.part_of_speech = v.clone();
                            }
                            if let Some(v) = &row.example_japanese {
                                word.example_japanese = v.clone();
                            }
                            if let Some(v) = &row.example_chinese {
                                word.example_chinese = v.clone();
                            }
                            if let Some(v) = &row.jlpt_level {
                                word.jlpt_level = v.clone();
                            }
                            if let Some(v) = &row.tags {
                                word.tags = v.clone();
                            }
                            word.updated_at = now;
                            db.upsert_word(word)?;
                            summary.updated += 1;
                        }
                    }
                } else {
                    let id = db.edit_word(
                        WordEdit {
                            id: None,
                            book_id: book,
                            expression: row.expression.clone(),
                            reading: row.reading.clone(),
                            meaning_chinese: row.meaning_chinese.clone(),
                            part_of_speech: row.part_of_speech.clone().unwrap_or_default(),
                            jlpt_level: row.jlpt_level.clone().unwrap_or_default(),
                            example_japanese: row.example_japanese.clone().unwrap_or_default(),
                            example_chinese: row.example_chinese.clone().unwrap_or_default(),
                            tags: row.tags.clone().unwrap_or_default(),
                            is_favorite: false,
                        },
                        now,
                    )?;
                    existing.insert(
                        key,
                        db.fetch_word(id)?
                            .ok_or(DatabaseError::InvalidData("imported word missing"))?,
                    );
                    summary.imported += 1;
                }
            }
            Ok(summary)
        })
    }
}
