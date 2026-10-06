use super::{models::*, repository::read_review_logs, Database, DatabaseError, Result};
use rusqlite::params;
#[derive(Debug, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HistoryRow {
    pub log: ReviewLog,
    pub rating_label: &'static str,
    pub transition: String,
}
#[derive(Debug, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HistoryPage {
    pub items: Vec<HistoryRow>,
    pub total: u32,
    pub limit: u32,
    pub offset: u32,
}
fn state(s: LearningState) -> &'static str {
    match s {
        LearningState::New => "未学习",
        LearningState::Learning => "学习",
        LearningState::Review => "复习",
        LearningState::Relearning => "重新学习",
        LearningState::Suspended => "已熟练",
    }
}
pub fn transition(log: &ReviewLog) -> String {
    let previous = if log.next_state != LearningState::Relearning
        && log.previous_state == LearningState::Review
        && log.previous_interval_days > 0
    {
        format!("{}天", log.previous_interval_days)
    } else {
        state(log.previous_state).into()
    };
    let next = if log.next_state == LearningState::Review && log.next_interval_days > 0 {
        format!("{}天", log.next_interval_days)
    } else {
        state(log.next_state).into()
    };
    format!("{previous} → {next}")
}
impl Database {
    pub fn word_history(&self, id: Id, limit: u32, offset: u32) -> Result<HistoryPage> {
        if !(1..=100).contains(&limit) {
            return Err(DatabaseError::InvalidData("invalid history page"));
        }
        let total = self.connection.query_row(
            "SELECT count(*) FROM review_logs WHERE word_id=?1",
            [id],
            |r| r.get(0),
        )?;
        let mut stmt=self.connection.prepare("SELECT id,word_id,reviewed_at,rating,previous_state,next_state,previous_interval_days,next_interval_days,scheduled_due_at,error_types,typed_answer,expected_answer,question_direction_raw_value,reading_wrong_count,spelling_wrong_count,repeated_wrong_count FROM review_logs WHERE word_id=?1 ORDER BY reviewed_at DESC,id LIMIT ?2 OFFSET ?3")?;
        let logs = stmt
            .query_map(params![id, limit, offset], read_review_logs)?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(HistoryPage {
            items: logs
                .into_iter()
                .map(|log| HistoryRow {
                    rating_label: match log.rating {
                        ReviewRating::Again => "忘记",
                        ReviewRating::Hard => "模糊",
                        ReviewRating::Good => "认识",
                        ReviewRating::Easy => "熟练",
                    },
                    transition: transition(&log),
                    log,
                })
                .collect(),
            total,
            limit,
            offset,
        })
    }
}
