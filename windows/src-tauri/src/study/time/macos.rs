use super::*;
use crate::srs::calendar::OffsetTransition;
use std::ffi::{c_char, c_void};
type Ref = *const c_void;
#[link(name = "CoreFoundation", kind = "framework")]
extern "C" {
    fn CFTimeZoneResetSystem();
    fn CFTimeZoneCopySystem() -> Ref;
    fn CFTimeZoneGetSecondsFromGMT(zone: Ref, at: f64) -> f64;
    fn CFTimeZoneGetNextDaylightSavingTimeTransition(zone: Ref, at: f64) -> f64;
    fn CFTimeZoneGetName(zone: Ref) -> Ref;
    fn CFStringGetCString(value: Ref, buffer: *mut c_char, size: isize, encoding: u32) -> u8;
    fn CFRelease(value: Ref);
}
struct Zone(Ref);
impl Drop for Zone {
    fn drop(&mut self) {
        unsafe {
            CFRelease(self.0);
        }
    }
}
const REFERENCE_EPOCH: f64 = 978_307_200.0;
fn absolute(t: Timestamp) -> f64 {
    t.0 as f64 / 1_000_000.0 - REFERENCE_EPOCH
}
fn offset(zone: Ref, at: f64) -> Result<i32> {
    // SAFETY: owned, non-null CFTimeZone lives throughout this call.
    let value = unsafe { CFTimeZoneGetSecondsFromGMT(zone, at) };
    if !value.is_finite() || value.abs() > 86400.0 || value.fract() != 0.0 {
        return Err(StudyError::timezone());
    }
    Ok(value as i32)
}
pub(super) fn context(start: Timestamp, end: Timestamp) -> Result<LocalTimeContext> {
    // SAFETY: system copy is retained and released once by Zone; no UI or data mutation.
    let zone = unsafe {
        CFTimeZoneResetSystem();
        Zone(CFTimeZoneCopySystem())
    };
    if zone.0.is_null() {
        return Err(StudyError::timezone());
    }
    let mut buffer = [0_i8; 512];
    // SAFETY: buffer is writable for its declared length; name belongs to live zone.
    let success = unsafe {
        CFStringGetCString(
            CFTimeZoneGetName(zone.0),
            buffer.as_mut_ptr(),
            buffer.len() as isize,
            0x08000100,
        )
    };
    if success == 0 {
        return Err(StudyError::timezone());
    }
    let name = buffer
        .iter()
        .take_while(|c| **c != 0)
        .map(|c| *c as u8)
        .collect::<Vec<_>>();
    let name = String::from_utf8(name).map_err(|_| StudyError::timezone())?;
    if name.is_empty() {
        return Err(StudyError::timezone());
    }
    let initial = offset(zone.0, absolute(start))?;
    let mut cursor = absolute(start);
    let mut transitions = Vec::new();
    for _ in 0..2048 {
        // SAFETY: retained timezone, finite Core Foundation absolute timestamp.
        let next = unsafe { CFTimeZoneGetNextDaylightSavingTimeTransition(zone.0, cursor) };
        if next == 0.0 || next >= absolute(end) {
            break;
        }
        if !next.is_finite() || next <= cursor {
            return Err(StudyError::timezone());
        }
        let at = Timestamp(((next + REFERENCE_EPOCH) * 1_000_000.0).round() as i64);
        transitions.push(OffsetTransition {
            at,
            offset_seconds: offset(zone.0, next + 1.0)?,
        });
        cursor = next + 1.0;
    }
    if transitions.len() == 2048 {
        return Err(StudyError::timezone());
    }
    Ok(LocalTimeContext {
        name,
        calendar: CalendarContext::new(start, end, initial, transitions)?,
    })
}
