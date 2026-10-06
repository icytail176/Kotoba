use super::*;
use crate::srs::calendar::OffsetTransition;
#[repr(C)]
#[derive(Clone, Copy, Default)]
struct SystemTime {
    year: u16,
    month: u16,
    weekday: u16,
    day: u16,
    hour: u16,
    minute: u16,
    second: u16,
    millis: u16,
}
#[repr(C)]
struct ZoneInfo {
    bias: i32,
    standard_name: [u16; 32],
    standard_date: SystemTime,
    standard_bias: i32,
    daylight_name: [u16; 32],
    daylight_date: SystemTime,
    daylight_bias: i32,
}
#[repr(C)]
struct DynamicZone {
    info: ZoneInfo,
    key: [u16; 128],
    disabled: u8,
}
#[link(name = "kernel32")]
extern "system" {
    fn GetDynamicTimeZoneInformation(info: *mut DynamicZone) -> u32;
    #[cfg(test)]
    fn EnumDynamicTimeZoneInformation(index: u32, info: *mut DynamicZone) -> u32;
    fn GetTimeZoneInformationForYear(
        year: u16,
        zone: *const DynamicZone,
        info: *mut ZoneInfo,
    ) -> i32;
    fn SystemTimeToTzSpecificLocalTimeEx(
        zone: *const DynamicZone,
        utc: *const SystemTime,
        local: *mut SystemTime,
    ) -> i32;
}
fn system(t: Timestamp) -> Result<SystemTime> {
    let (y, m, d, h, min, s) = utc_parts(t)?;
    Ok(SystemTime {
        year: y as u16,
        month: m,
        day: d,
        hour: h,
        minute: min,
        second: s,
        ..Default::default()
    })
}
fn offset(zone: &DynamicZone, at: Timestamp) -> Result<i32> {
    let utc = system(at)?;
    let mut local = SystemTime::default();
    // SAFETY: correctly sized repr(C) structures, immutable live timezone, writable output.
    if unsafe { SystemTimeToTzSpecificLocalTimeEx(zone, &utc, &mut local) } == 0 {
        return Err(StudyError::timezone());
    }
    let value = (civil_micros(
        i32::from(local.year),
        local.month,
        local.day,
        local.hour,
        local.minute,
        local.second,
    )? - civil_micros(
        i32::from(utc.year),
        utc.month,
        utc.day,
        utc.hour,
        utc.minute,
        utc.second,
    )?) / 1_000_000;
    i32::try_from(value).map_err(|_| StudyError::timezone())
}
fn transition(year: i32, date: SystemTime, before: i32) -> Result<Timestamp> {
    if date.month == 0 {
        return Err(StudyError::timezone());
    }
    let day = if date.year != 0 {
        date.day
    } else {
        if !(1..=5).contains(&date.day) || date.weekday > 6 {
            return Err(StudyError::timezone());
        }
        let first = civil_micros(year, date.month, 1, 0, 0, 0)?.div_euclid(DAY_MICROS);
        let weekday = (first + 4).rem_euclid(7) as u16;
        let mut day = 1 + (date.weekday + 7 - weekday) % 7 + 7 * (date.day - 1);
        if day > month_days(year, date.month) {
            day -= 7;
        }
        day
    };
    Ok(Timestamp(
        civil_micros(year, date.month, day, date.hour, date.minute, date.second)?
            - i64::from(before) * 1_000_000,
    ))
}
pub(super) fn context(start: Timestamp, end: Timestamp) -> Result<LocalTimeContext> {
    // SAFETY: zero is valid initialization for integer-only Win32 output structures.
    let mut zone: DynamicZone = unsafe { std::mem::zeroed() };
    // SAFETY: correctly sized writable dynamic timezone structure.
    if unsafe { GetDynamicTimeZoneInformation(&mut zone) } == u32::MAX {
        return Err(StudyError::timezone());
    }
    context_for_zone(&zone, start, end)
}
fn context_for_zone(
    zone: &DynamicZone,
    start: Timestamp,
    end: Timestamp,
) -> Result<LocalTimeContext> {
    let name = String::from_utf16(
        zone.key
            .split(|v| *v == 0)
            .next()
            .ok_or_else(StudyError::timezone)?,
    )
    .map_err(|_| StudyError::timezone())?;
    if name.is_empty() {
        return Err(StudyError::timezone());
    }
    let initial = offset(zone, start)?;
    let first_year = utc_parts(start)?.0 - 1;
    let last_year = utc_parts(end)?.0 + 1;
    let mut transitions = Vec::new();
    for year in first_year..=last_year {
        // SAFETY: zero initialized output; native API fills complete year-specific rules.
        let mut info: ZoneInfo = unsafe { std::mem::zeroed() };
        if unsafe { GetTimeZoneInformationForYear(year as u16, zone, &mut info) } == 0 {
            return Err(StudyError::timezone());
        }
        if zone.disabled == 0 && info.standard_date.month != 0 && info.daylight_date.month != 0 {
            for (date, before) in [
                (
                    info.daylight_date,
                    bias_offset(info.bias, info.standard_bias)?,
                ),
                (
                    info.standard_date,
                    bias_offset(info.bias, info.daylight_bias)?,
                ),
            ] {
                let at = transition(year, date, before)?;
                if at.0 > start.0 && at.0 < end.0 {
                    transitions.push(OffsetTransition {
                        at,
                        offset_seconds: offset(zone, Timestamp(at.0 + 1_000_000))?,
                    });
                }
            }
        }
    }
    transitions.sort_by_key(|t| t.at.0);
    transitions.dedup_by_key(|t| t.at.0);
    Ok(LocalTimeContext {
        name,
        calendar: CalendarContext::new(start, end, initial, transitions)?,
    })
}

fn bias_offset(bias: i32, adjustment: i32) -> Result<i32> {
    bias.checked_add(adjustment)
        .and_then(i32::checked_neg)
        .and_then(|v| v.checked_mul(60))
        .ok_or_else(StudyError::timezone)
}
#[cfg(test)]
mod tests {
    use super::*;
    fn named_zone(name: &str) -> DynamicZone {
        for index in 0..1024 {
            // SAFETY: integer-only repr(C) output, filled by the enumeration API.
            let mut zone: DynamicZone = unsafe { std::mem::zeroed() };
            let result = unsafe { EnumDynamicTimeZoneInformation(index, &mut zone) };
            if result == 259 {
                break;
            }
            assert_eq!(result, 0, "native Windows timezone enumeration failed");
            let end = zone
                .key
                .iter()
                .position(|v| *v == 0)
                .unwrap_or(zone.key.len());
            if String::from_utf16(&zone.key[..end]).expect("native UTF-16") == name {
                return zone;
            }
        }
        panic!("required Windows registry timezone missing: {name}");
    }
    fn at(y: i32, m: u16, d: u16, h: u16, min: u16) -> Timestamp {
        Timestamp(civil_micros(y, m, d, h, min, 0).expect("test date"))
    }
    #[test]
    fn native_windows_registry_rules_cover_pacific_spring_and_fall() {
        let zone = named_zone("Pacific Standard Time");
        let context = context_for_zone(&zone, at(2026, 1, 1, 0, 0), at(2027, 1, 1, 0, 0)).unwrap();
        assert_eq!(context.name, "Pacific Standard Time");
        // 12:00 local -> 12:00 local: 23h in spring, 25h in fall.
        assert_eq!(
            context.calendar.add_days(at(2026, 3, 7, 20, 0), 1).unwrap(),
            at(2026, 3, 8, 19, 0)
        );
        assert_eq!(
            context
                .calendar
                .add_days(at(2026, 10, 31, 19, 0), 1)
                .unwrap(),
            at(2026, 11, 1, 20, 0)
        );
    }
    #[test]
    fn native_windows_registry_rules_cover_lord_howe_half_hour_and_utc() {
        let zone = named_zone("Lord Howe Standard Time");
        let context = context_for_zone(&zone, at(2026, 1, 1, 0, 0), at(2027, 1, 1, 0, 0)).unwrap();
        // UTC 01:00 = local noon before the southern-hemisphere fall transition.
        assert_eq!(
            context.calendar.add_days(at(2026, 4, 4, 1, 0), 1).unwrap(),
            at(2026, 4, 5, 1, 30)
        );
        let utc = named_zone("UTC");
        let context = context_for_zone(&utc, at(2026, 1, 1, 0, 0), at(2027, 1, 1, 0, 0)).unwrap();
        assert_eq!(
            context
                .calendar
                .add_days(at(2026, 3, 7, 12, 0), 60)
                .unwrap(),
            at(2026, 5, 6, 12, 0)
        );
        assert!(bias_offset(i32::MAX, 1).is_err());
    }
}
