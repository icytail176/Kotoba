use super::{DatabaseError, Result};
use rusqlite::{Connection, TransactionBehavior};

const MIGRATIONS: &[(u32, &str)] = &[(1, include_str!("schema_1.sql"))];

pub(super) fn apply(connection: &mut Connection) -> Result<()> {
    apply_plan(connection, MIGRATIONS)?;
    // Validate the current shape as well as the version marker; never recreate a
    // malformed existing database. Future migrations extend this validation.
    for statement in [
        "SELECT id,name,book_description,created_at,updated_at,is_built_in FROM word_books LIMIT 0",
        "SELECT id,japanese,kana,chinese_meaning,part_of_speech,jlpt_level,example_japanese,example_chinese,tags,created_at,updated_at,is_archived,is_favorite,loanword_source_term,loanword_source_language_code,loanword_is_wasei,loanword_is_partial,word_book_id FROM vocabulary_words LIMIT 0",
        "SELECT id,word_id,state,due_at,interval_days,review_count,lapse_count,last_reviewed_at,created_at,updated_at FROM learning_progress LIMIT 0",
        "SELECT id,word_id,reviewed_at,rating,previous_state,next_state,previous_interval_days,next_interval_days,scheduled_due_at,error_types,typed_answer,expected_answer,question_direction_raw_value,reading_wrong_count,spelling_wrong_count,repeated_wrong_count FROM review_logs LIMIT 0",
    ] { connection.prepare(statement)?; }
    Ok(())
}

pub(super) fn apply_plan(connection: &mut Connection, plan: &[(u32, &str)]) -> Result<()> {
    let transaction = connection.transaction_with_behavior(TransactionBehavior::Immediate)?;
    let current: i64 = transaction.pragma_query_value(None, "user_version", |row| row.get(0))?;
    let supported = plan.last().map_or(0, |(version, _)| *version);
    if current < 0 || current > i64::from(supported) {
        return Err(DatabaseError::UnsupportedSchema(current));
    }
    let mut version = current;
    for (next, sql) in plan {
        if i64::from(*next) <= version {
            continue;
        }
        if i64::from(*next) != version + 1 {
            return Err(DatabaseError::InvalidData(
                "migration versions must be consecutive",
            ));
        }
        transaction
            .execute_batch(sql)
            .map_err(|source| DatabaseError::Migration {
                version: *next,
                source,
            })?;
        transaction.pragma_update(None, "user_version", next)?;
        version = i64::from(*next);
    }
    transaction.commit()?;
    Ok(())
}
