//! Host timezone access belongs here, never in the pure SRS core.
use super::models::{Result, StudyError};
use crate::{
    db::models::Timestamp,
    srs::{calendar::CalendarContext, models::DAY_MICROS},
};
#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "windows")]
mod windows;
pub struct LocalTimeContext {
    pub name: String,
    pub calendar: CalendarContext,
}
pub trait LocalTimeContextProvider {
    fn context(&self, now: Timestamp) -> Result<LocalTimeContext>;
}
pub struct SystemLocalTimeContextProvider;
impl LocalTimeContextProvider for SystemLocalTimeContextProvider {
    fn context(&self, now: Timestamp) -> Result<LocalTimeContext> {
        let start = Timestamp(
            now.0
                .checked_sub(3 * DAY_MICROS)
                .ok_or_else(StudyError::timezone)?,
        );
        let end = Timestamp(
            now.0
                .checked_add(65 * DAY_MICROS)
                .ok_or_else(StudyError::timezone)?,
        );
        self.context_between(start, end)
    }
}
impl SystemLocalTimeContextProvider {
    pub fn context_between(&self, start: Timestamp, end: Timestamp) -> Result<LocalTimeContext> {
        #[cfg(target_os = "macos")]
        {
            macos::context(start, end)
        }
        #[cfg(target_os = "windows")]
        {
            windows::context(start, end)
        }
        #[cfg(not(any(target_os = "macos", target_os = "windows")))]
        {
            let _ = (start, end);
            Err(StudyError::timezone())
        }
    }
}
pub fn now() -> Result<Timestamp> {
    let value = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|_| StudyError::invalid())?
        .as_micros();
    Ok(Timestamp(
        i64::try_from(value).map_err(|_| StudyError::invalid())?,
    ))
}
#[cfg(any(target_os = "windows", test))]
pub(crate) fn month_days(y: i32, m: u16) -> u16 {
    match m {
        2 => {
            if y % 4 == 0 && (y % 100 != 0 || y % 400 == 0) {
                29
            } else {
                28
            }
        }
        4 | 6 | 9 | 11 => 30,
        _ => 31,
    }
}
#[cfg(any(target_os = "windows", test))]
pub(crate) fn civil_micros(y: i32, m: u16, d: u16, h: u16, min: u16, s: u16) -> Result<i64> {
    if !(1601..=9999).contains(&y)
        || !(1..=12).contains(&m)
        || d == 0
        || d > month_days(y, m)
        || h > 23
        || min > 59
        || s > 59
    {
        return Err(StudyError::timezone());
    }
    let before = |year: i64| {
        let n = year - 1;
        365 * n + n / 4 - n / 100 + n / 400
    };
    let days = before(i64::from(y)) - before(1970)
        + (1..m)
            .map(|month| i64::from(month_days(y, month)))
            .sum::<i64>()
        + i64::from(d - 1);
    Ok(days * DAY_MICROS + (i64::from(h) * 3600 + i64::from(min) * 60 + i64::from(s)) * 1_000_000)
}
#[cfg(any(target_os = "windows", test))]
pub(crate) fn utc_parts(t: Timestamp) -> Result<(i32, u16, u16, u16, u16, u16)> {
    let day = t.0.div_euclid(DAY_MICROS);
    let mut y = 1970;
    while civil_micros(y + 1, 1, 1, 0, 0, 0)?.div_euclid(DAY_MICROS) <= day {
        y += 1;
    }
    while civil_micros(y, 1, 1, 0, 0, 0)?.div_euclid(DAY_MICROS) > day {
        y -= 1;
    }
    let mut remaining = day - civil_micros(y, 1, 1, 0, 0, 0)?.div_euclid(DAY_MICROS);
    let mut m = 1;
    while remaining >= i64::from(month_days(y, m)) {
        remaining -= i64::from(month_days(y, m));
        m += 1;
    }
    let seconds = t.0.rem_euclid(DAY_MICROS) / 1_000_000;
    Ok((
        y,
        m,
        (remaining + 1) as u16,
        (seconds / 3600) as u16,
        ((seconds % 3600) / 60) as u16,
        (seconds % 60) as u16,
    ))
}
