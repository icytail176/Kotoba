//! Explicit civil-time rules, never the test runner's timezone. Phase 6 supplies
//! the user's current timezone rules; no implicit UTC fallback for day schedules.
use super::models::*;
use crate::db::models::Timestamp;

#[derive(Debug, Clone, Copy)]
pub struct OffsetTransition {
    pub at: Timestamp,
    pub offset_seconds: i32,
}
#[derive(Debug, Clone)]
pub struct CalendarContext {
    start: Timestamp,
    end: Timestamp,
    initial_offset: i32,
    transitions: Vec<OffsetTransition>,
}
impl CalendarContext {
    pub fn fixed(offset_seconds: i32) -> Result<Self> {
        Self::new(
            Timestamp(i64::MIN),
            Timestamp(i64::MAX),
            offset_seconds,
            Vec::new(),
        )
    }
    /// Rules must completely cover [start,end), including every offset change.
    pub fn new(
        start: Timestamp,
        end: Timestamp,
        initial_offset: i32,
        transitions: Vec<OffsetTransition>,
    ) -> Result<Self> {
        let valid_offset = |offset: i32| offset.unsigned_abs() <= 86_400;
        if start.0 >= end.0 || !valid_offset(initial_offset) {
            return Err(SrsError::InvalidCalendar);
        }
        let mut previous = start.0;
        for transition in &transitions {
            if transition.at.0 <= previous
                || transition.at.0 >= end.0
                || !valid_offset(transition.offset_seconds)
            {
                return Err(SrsError::InvalidCalendar);
            }
            previous = transition.at.0;
        }
        Ok(Self {
            start,
            end,
            initial_offset,
            transitions,
        })
    }
    fn offset(&self, instant: i64) -> Result<i64> {
        if instant < self.start.0 || instant >= self.end.0 {
            return Err(SrsError::CalendarCoverage);
        }
        let index = self.transitions.partition_point(|t| t.at.0 <= instant);
        Ok(i64::from(if index == 0 {
            self.initial_offset
        } else {
            self.transitions[index - 1].offset_seconds
        }) * 1_000_000)
    }
    fn local(&self, now: Timestamp) -> Result<i64> {
        now.0
            .checked_add(self.offset(now.0)?)
            .ok_or(SrsError::DateOverflow)
    }
    fn resolve(&self, local: i64) -> Result<Timestamp> {
        let mut earliest: Option<i64> = None;
        for offset in std::iter::once(self.initial_offset)
            .chain(self.transitions.iter().map(|t| t.offset_seconds))
        {
            let offset = i64::from(offset) * 1_000_000;
            if let Some(utc) = local.checked_sub(offset) {
                if self.offset(utc).ok() == Some(offset) {
                    earliest = Some(earliest.map_or(utc, |old| old.min(utc)));
                }
            }
        }
        if let Some(utc) = earliest {
            return Ok(Timestamp(utc));
        }
        // Foundation Calendar day addition chooses the first repeated time, and
        // shifts a nonexistent wall time forward by the gap, preserving minutes.
        let mut before = i64::from(self.initial_offset) * 1_000_000;
        for transition in &self.transitions {
            let after = i64::from(transition.offset_seconds) * 1_000_000;
            let low = transition
                .at
                .0
                .checked_add(before)
                .ok_or(SrsError::DateOverflow)?;
            let high = transition
                .at
                .0
                .checked_add(after)
                .ok_or(SrsError::DateOverflow)?;
            if after > before && (low..high).contains(&local) {
                let utc = local.checked_sub(before).ok_or(SrsError::DateOverflow)?;
                self.offset(utc)?;
                return Ok(Timestamp(utc));
            }
            before = after;
        }
        Err(SrsError::CalendarCoverage)
    }
    pub fn day_index(&self, now: Timestamp) -> Result<i64> {
        Ok(self.local(now)?.div_euclid(DAY_MICROS))
    }
    pub fn day_start(&self, now: Timestamp) -> Result<Timestamp> {
        self.resolve(
            self.day_index(now)?
                .checked_mul(DAY_MICROS)
                .ok_or(SrsError::DateOverflow)?,
        )
    }
    pub fn add_days(&self, now: Timestamp, days: i64) -> Result<Timestamp> {
        let duration = days.checked_mul(DAY_MICROS).ok_or(SrsError::DateOverflow)?;
        let target = self
            .local(now)?
            .checked_add(duration)
            .ok_or(SrsError::DateOverflow)?;
        self.resolve(target)
    }
    pub fn day_end_exclusive(&self, now: Timestamp) -> Result<Timestamp> {
        let target = self
            .local(now)?
            .div_euclid(DAY_MICROS)
            .checked_add(1)
            .and_then(|day| day.checked_mul(DAY_MICROS))
            .ok_or(SrsError::DateOverflow)?;
        self.resolve(target)
    }
}
