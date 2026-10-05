use super::{calendar::CalendarContext, models::*};
use crate::db::models::{LearningState as State, ReviewRating as Rating, Timestamp};

pub fn schedule(
    progress: &ProgressSnapshot,
    rating: FormalRating,
    now: Timestamp,
    previous_formal: Option<Rating>,
    archived: bool,
    calendar: &CalendarContext,
) -> Result<Schedule> {
    if progress.interval_days < 0 || progress.review_count < 0 || progress.lapse_count < 0 {
        return Err(SrsError::InvalidProgress);
    }
    // Matches the Mac pure scheduler's no-op. The transaction service rejects
    // suspended submissions before scheduling, because they cannot enter a queue.
    if progress.state == State::Suspended {
        return Ok(Schedule {
            state: State::Suspended,
            interval_days: progress.interval_days,
            due_at: now,
            review_count: progress.review_count,
            lapse_count: progress.lapse_count,
            did_lapse: false,
            automatic_mastery: false,
        });
    }
    let review_count = progress
        .review_count
        .checked_add(1)
        .ok_or(SrsError::CounterOverflow)?;
    let mut result = Schedule {
        state: State::Review,
        interval_days: 0,
        due_at: now,
        review_count,
        lapse_count: progress.lapse_count,
        did_lapse: false,
        automatic_mastery: false,
    };
    result.automatic_mastery = progress.state == State::Review
        && progress.interval_days == MAX_INTERVAL_DAYS
        && !archived
        && previous_formal == Some(Rating::Good)
        && rating.0 == Rating::Good;
    if rating.0 == Rating::Easy || result.automatic_mastery {
        result.state = State::Suspended;
        return Ok(result);
    }
    if rating.0 == Rating::Again {
        result.did_lapse = matches!(progress.state, State::Review | State::Relearning);
        result.state = if result.did_lapse {
            State::Relearning
        } else {
            State::Learning
        };
        if result.did_lapse {
            result.lapse_count = result
                .lapse_count
                .checked_add(1)
                .ok_or(SrsError::CounterOverflow)?;
        }
        result.due_at = Timestamp(
            now.0
                .checked_add(10 * MINUTE_MICROS)
                .ok_or(SrsError::DateOverflow)?,
        );
    } else {
        let interval = if progress.state == State::Review {
            let days = progress.interval_days.min(MAX_INTERVAL_DAYS);
            if rating.0 == Rating::Hard {
                (days * 6 + 4) / 5
            } else {
                days * 2
            }
        } else if rating.0 == Rating::Hard {
            1
        } else {
            2
        };
        result.interval_days = interval.clamp(1, MAX_INTERVAL_DAYS);
        result.due_at = calendar.add_days(now, result.interval_days)?;
    }
    Ok(result)
}
