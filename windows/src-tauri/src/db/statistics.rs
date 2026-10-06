//! Current Mac statistics contract, aggregated in SQLite using explicit civil days.
use super::{models::*, Database, DatabaseError, Result};
use crate::srs::calendar::CalendarContext;
use rusqlite::{functions::FunctionFlags, params};
use serde::Serialize;
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Activity {
    pub day: Timestamp,
    pub total_count: u32,
    pub new_word_count: u32,
    pub review_count: u32,
}
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ForecastDay {
    pub day: Timestamp,
    pub count: u32,
}
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LapsedWord {
    pub id: Id,
    pub expression: String,
    pub reading: String,
    pub meaning_chinese: String,
    pub lapse_count: u32,
}
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Statistics {
    pub days: u32,
    pub timezone: String,
    pub today_new_word_count: u32,
    pub today_review_count: u32,
    pub total_learned_word_count: u32,
    pub total_review_count: u32,
    pub current_streak_days: u32,
    pub period_formal_review_count: u32,
    pub period_newly_learned_word_count: u32,
    pub period_manual_mastery_count: u32,
    pub period_automatic_mastery_count: u32,
    pub rating_distribution: [u32; 4],
    pub spelling_passed: u32,
    pub spelling_eligible: u32,
    pub daily_activity: Vec<Activity>,
    pub top_lapsed_words: Vec<LapsedWord>,
}
fn calendar_error(_: crate::srs::models::SrsError) -> DatabaseError {
    DatabaseError::InvalidData("local calendar coverage unavailable")
}
impl Database {
    pub fn earliest_log(&self) -> Result<Option<Timestamp>> {
        Ok(self
            .connection
            .query_row("SELECT min(reviewed_at) FROM review_logs", [], |r| r.get(0))?)
    }
    pub fn forecast(
        &self,
        now: Timestamp,
        calendar: &CalendarContext,
        book: Option<Id>,
    ) -> Result<Vec<ForecastDay>> {
        let today = calendar.day_start(now).map_err(calendar_error)?;
        let mut days = Vec::new();
        for index in 0..7 {
            let start = calendar.add_days(today, index).map_err(calendar_error)?;
            let end = calendar
                .add_days(today, index + 1)
                .map_err(calendar_error)?;
            let count=self.connection.query_row("SELECT count(*) FROM learning_progress p JOIN vocabulary_words w ON w.id=p.word_id WHERE w.is_archived=0 AND (?1 IS NULL OR w.word_book_id=?1) AND p.state IN ('learning','relearning','review') AND p.due_at<?2 AND (?3=0 OR p.due_at>=?4)",params![book,end,index,start],|r|r.get(0))?;
            days.push(ForecastDay { day: start, count });
        }
        Ok(days)
    }
    pub fn statistics(
        &self,
        now: Timestamp,
        calendar: &CalendarContext,
        timezone: String,
        days: u32,
    ) -> Result<Statistics> {
        if ![7, 30].contains(&days) {
            return Err(DatabaseError::InvalidData(
                "statistics range must be 7 or 30",
            ));
        }
        let today = calendar.day_start(now).map_err(calendar_error)?;
        let start = calendar
            .add_days(today, -i64::from(days - 1))
            .map_err(calendar_error)?;
        let end = calendar.add_days(today, 1).map_err(calendar_error)?;
        let (today_new_word_count,today_review_count)=self.connection.query_row("SELECT count(DISTINCT CASE WHEN previous_state='new' THEN word_id END),coalesce(sum(previous_state!='new'),0) FROM review_logs WHERE reviewed_at>=?1 AND reviewed_at<?2",params![today,end],|r|Ok((r.get(0)?,r.get(1)?)))?;
        let (total_learned_word_count, total_review_count) = self.connection.query_row(
            "SELECT count(DISTINCT word_id),count(*) FROM review_logs",
            [],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )?;
        let (period_formal_review_count,period_manual_mastery_count,period_automatic_mastery_count,again,hard,good,easy)=self.connection.query_row("SELECT count(*),coalesce(sum(rating='easy' AND next_state='suspended'),0),coalesce(sum(rating='good' AND next_state='suspended'),0),coalesce(sum(rating='again'),0),coalesce(sum(rating='hard'),0),coalesce(sum(rating='good'),0),coalesce(sum(rating='easy'),0) FROM review_logs WHERE reviewed_at>=?1 AND reviewed_at<?2",params![start,end],|r|Ok((r.get(0)?,r.get(1)?,r.get(2)?,r.get(3)?,r.get(4)?,r.get(5)?,r.get(6)?)))?;
        let period_newly_learned_word_count=self.connection.query_row("SELECT count(*) FROM (SELECT min(reviewed_at) AS first FROM review_logs GROUP BY word_id) WHERE first>=?1 AND first<?2",params![start,end],|r|r.get(0))?;
        self.connection.create_scalar_function("statistics_han",1,FunctionFlags::SQLITE_UTF8|FunctionFlags::SQLITE_DETERMINISTIC,|ctx|Ok(ctx.get::<String>(0)?.chars().any(|c|matches!(c as u32,0x3400..=0x4dbf|0x4e00..=0x9fff|0xf900..=0xfaff|0x20000..=0x2fa1f))))?;
        let (spelling_passed,spelling_eligible)=self.connection.query_row("SELECT coalesce(sum((l.spelling_wrong_count=0)+(statistics_han(w.japanese) AND l.reading_wrong_count=0)),0),coalesce(sum(1+statistics_han(w.japanese)),0) FROM review_logs l JOIN vocabulary_words w ON w.id=l.word_id WHERE w.is_archived=0 AND l.next_state!='suspended' AND trim(coalesce(l.question_direction_raw_value,''))!='' AND l.reviewed_at>=?1 AND l.reviewed_at<?2",params![start,end],|r|Ok((r.get(0)?,r.get(1)?)))?;
        let rules = calendar.clone();
        self.connection.create_scalar_function(
            "statistics_day",
            1,
            FunctionFlags::SQLITE_UTF8 | FunctionFlags::SQLITE_DETERMINISTIC,
            move |ctx| {
                rules
                    .day_index(Timestamp(ctx.get(0)?))
                    .map_err(|e| rusqlite::Error::UserFunctionError(Box::new(e)))
            },
        )?;
        let current_streak_days = (|| -> Result<u32> {
            let mut stmt=self.connection.prepare("SELECT DISTINCT statistics_day(reviewed_at) FROM review_logs WHERE reviewed_at<?1 ORDER BY 1 DESC")?;
            let mut rows = stmt.query([end])?;
            let mut cursor = calendar.day_index(now).map_err(calendar_error)?;
            let mut count = 0;
            while let Some(row) = rows.next()? {
                let day: i64 = row.get(0)?;
                if day != cursor {
                    break;
                }
                count += 1;
                cursor -= 1;
            }
            Ok(count)
        })();
        self.connection.remove_function("statistics_day", 1)?;
        let current_streak_days = current_streak_days?;
        let mut daily_activity = Vec::new();
        for index in 0..days {
            let day = calendar
                .add_days(start, i64::from(index))
                .map_err(calendar_error)?;
            let finish = calendar.add_days(day, 1).map_err(calendar_error)?;
            let (total_count,new_word_count,review_count)=self.connection.query_row("SELECT count(*),count(DISTINCT CASE WHEN previous_state='new' THEN word_id END),coalesce(sum(previous_state!='new'),0) FROM review_logs WHERE reviewed_at>=?1 AND reviewed_at<?2",params![day,finish],|r|Ok((r.get(0)?,r.get(1)?,r.get(2)?)))?;
            daily_activity.push(Activity {
                day,
                total_count,
                new_word_count,
                review_count,
            });
        }
        let mut stmt=self.connection.prepare("SELECT w.id,w.japanese,w.kana,w.chinese_meaning,count(*) FROM review_logs l JOIN vocabulary_words w ON w.id=l.word_id WHERE w.is_archived=0 AND l.rating='again' AND l.previous_state IN ('review','relearning') GROUP BY w.id ORDER BY count(*) DESC,w.japanese,w.id LIMIT 10")?;
        let top_lapsed_words = stmt
            .query_map([], |r| {
                Ok(LapsedWord {
                    id: r.get(0)?,
                    expression: r.get(1)?,
                    reading: r.get(2)?,
                    meaning_chinese: r.get(3)?,
                    lapse_count: r.get(4)?,
                })
            })?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(Statistics {
            days,
            timezone,
            today_new_word_count,
            today_review_count,
            total_learned_word_count,
            total_review_count,
            current_streak_days,
            period_formal_review_count,
            period_newly_learned_word_count,
            period_manual_mastery_count,
            period_automatic_mastery_count,
            rating_distribution: [again, hard, good, easy],
            spelling_passed,
            spelling_eligible,
            daily_activity,
            top_lapsed_words,
        })
    }
}
