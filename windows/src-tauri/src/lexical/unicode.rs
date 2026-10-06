//! Unicode normalization provided by the native OS, with no formatter dependency.
//! Mac uses the same Core Foundation normalization/folding as the source app.

pub fn trim(value: &str) -> &str {
    value.trim_matches(|c: char| c.is_whitespace() || c == '\u{200b}')
}

#[cfg(target_os = "macos")]
mod native {
    use std::ffi::c_void;
    type Ref = *const c_void;
    #[repr(C)]
    struct Range {
        location: isize,
        length: isize,
    }
    #[link(name = "CoreFoundation", kind = "framework")]
    extern "C" {
        fn CFStringCreateWithCharacters(allocator: Ref, chars: *const u16, count: isize) -> Ref;
        fn CFStringCreateMutableCopy(allocator: Ref, capacity: isize, source: Ref) -> Ref;
        fn CFStringNormalize(value: Ref, form: isize);
        fn CFStringFold(value: Ref, flags: usize, locale: Ref);
        fn CFLocaleCreate(allocator: Ref, identifier: Ref) -> Ref;
        fn CFStringGetLength(value: Ref) -> isize;
        fn CFStringGetCharacters(value: Ref, range: Range, chars: *mut u16);
        fn CFRelease(value: Ref);
    }
    struct Owned(Ref);
    impl Drop for Owned {
        fn drop(&mut self) {
            if !self.0.is_null() {
                unsafe {
                    CFRelease(self.0);
                }
            }
        }
    }
    fn string(value: &str) -> Owned {
        let chars: Vec<u16> = value.encode_utf16().collect();
        // SAFETY: the API copies valid UTF-16; the returned object is owned.
        Owned(unsafe {
            CFStringCreateWithCharacters(std::ptr::null(), chars.as_ptr(), chars.len() as isize)
        })
    }
    pub(super) fn normalize(value: &str, fold: bool) -> String {
        let source = string(value);
        if source.0.is_null() {
            return value.to_owned();
        }
        let result = Owned(unsafe { CFStringCreateMutableCopy(std::ptr::null(), 0, source.0) });
        if result.0.is_null() {
            return value.to_owned();
        }
        // SAFETY: retained mutable string, valid normalization enum constants.
        unsafe {
            CFStringNormalize(result.0, if fold { 3 } else { 2 });
        }
        if fold {
            let identifier = string("en_US_POSIX");
            let locale = Owned(unsafe { CFLocaleCreate(std::ptr::null(), identifier.0) });
            unsafe {
                CFStringFold(result.0, 1 | 128 | 256, locale.0);
                CFStringNormalize(result.0, 2);
            }
        }
        let length = unsafe { CFStringGetLength(result.0) };
        if length < 0 {
            return value.to_owned();
        }
        let mut chars = vec![0_u16; length as usize];
        unsafe {
            CFStringGetCharacters(
                result.0,
                Range {
                    location: 0,
                    length,
                },
                chars.as_mut_ptr(),
            );
        }
        String::from_utf16(&chars).unwrap_or_else(|_| value.to_owned())
    }
}

#[cfg(target_os = "windows")]
mod native {
    #[link(name = "normaliz")]
    extern "system" {
        fn NormalizeString(
            form: i32,
            source: *const u16,
            length: i32,
            result: *mut u16,
            capacity: i32,
        ) -> i32;
    }
    fn normalized(value: &str, form: i32) -> String {
        let input: Vec<u16> = value.encode_utf16().collect();
        if input.is_empty() {
            return String::new();
        }
        let Ok(length) = i32::try_from(input.len()) else {
            return value.to_owned();
        };
        // SAFETY: valid UTF-16 buffers and explicit lengths; first call determines capacity.
        let size =
            unsafe { NormalizeString(form, input.as_ptr(), length, std::ptr::null_mut(), 0) };
        if size <= 0 {
            return value.to_owned();
        }
        let mut output = vec![0_u16; size as usize];
        let written =
            unsafe { NormalizeString(form, input.as_ptr(), length, output.as_mut_ptr(), size) };
        if written <= 0 {
            return value.to_owned();
        }
        output.truncate(written as usize);
        String::from_utf16(&output).unwrap_or_else(|_| value.to_owned())
    }
    pub(super) fn normalize(value: &str, fold: bool) -> String {
        if !fold {
            return normalized(value, 1);
        }
        // Foundation diacritic folding retains Japanese voiced marks, unlike Latin accents.
        let decomposed = normalized(value, 6);
        let folded: String = decomposed
            .chars()
            .filter(|c| {
                !matches!(*c as u32,
            0x0300..=0x036f | 0x1ab0..=0x1aff | 0x1dc0..=0x1dff | 0x20d0..=0x20ff | 0xfe20..=0xfe2f)
            })
            .flat_map(char::to_lowercase)
            .collect();
        normalized(&folded, 1)
    }
}

pub fn nfc(value: &str) -> String {
    #[cfg(any(target_os = "macos", target_os = "windows"))]
    {
        native::normalize(value, false)
    }
    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    {
        value.to_owned()
    }
}
pub fn search_key(value: &str) -> String {
    #[cfg(any(target_os = "macos", target_os = "windows"))]
    {
        native::normalize(trim(value), true)
    }
    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    {
        trim(value).to_lowercase()
    }
}
