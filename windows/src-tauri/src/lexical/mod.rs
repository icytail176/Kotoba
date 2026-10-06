pub mod conjugation;
mod godan_map;
mod kana_map;
pub mod preview;
#[cfg(test)]
mod tests;
pub mod unicode;

pub fn romaji(reading: &str) -> String {
    let kana: Vec<char> = unicode::nfc(reading)
        .chars()
        .map(|c| {
            if (0x30a1..=0x30f6).contains(&(c as u32)) {
                char::from_u32(c as u32 - 0x60).unwrap_or(c)
            } else {
                c
            }
        })
        .collect();
    let mut raw = String::new();
    let mut index = 0;
    let mut geminate = false;
    while index < kana.len() {
        let c = kana[index];
        if c == 'っ' {
            geminate = true;
            index += 1;
            continue;
        }
        if c == 'ー' {
            if let Some((at, vowel)) = raw
                .char_indices()
                .rev()
                .find(|(_, v)| "aeiouāīūēō".contains(*v))
            {
                let replacement = match vowel {
                    'a' | 'ā' => "ā",
                    'i' | 'ī' => "ī",
                    'u' | 'ū' => "ū",
                    'e' | 'ē' => "ē",
                    _ => "ō",
                };
                raw.replace_range(at..at + vowel.len_utf8(), replacement);
            }
            index += 1;
            continue;
        }
        let pair: String = kana[index..(index + 2).min(kana.len())].iter().collect();
        let single = c.to_string();
        let syllable = if c == 'ん' {
            index += 1;
            Some(
                if kana
                    .get(index)
                    .is_some_and(|c| "あいうえおやゆよぁぃぅぇぉゃゅょ".contains(*c))
                {
                    "n'"
                } else {
                    "n"
                },
            )
        } else if let Some((_, value)) = kana_map::COMBINATIONS.iter().find(|(key, _)| *key == pair)
        {
            index += 2;
            Some(*value)
        } else if let Some((_, value)) = kana_map::SYLLABLES.iter().find(|(key, _)| *key == single)
        {
            index += 1;
            Some(*value)
        } else {
            None
        };
        if let Some(value) = syllable {
            if geminate {
                if value.starts_with("ch") {
                    raw.push('t');
                } else if let Some(first) = value.chars().next().filter(|c| !"aeioun".contains(*c))
                {
                    raw.push(first);
                }
                geminate = false;
            }
            raw.push_str(value);
        } else {
            raw.push(c);
            index += 1;
            geminate = false;
        }
    }
    for (from, to) in [
        ("aa", "ā"),
        ("ii", "ī"),
        ("uu", "ū"),
        ("ee", "ē"),
        ("oo", "ō"),
        ("ou", "ō"),
    ] {
        raw = raw.replace(from, to);
    }
    raw
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Pitch {
    pub display_text: String,
    pub accessibility_text: String,
}
pub fn pitch(tags: &[String]) -> Option<Pitch> {
    let source = unicode::trim(
        tags.iter()
            .find(|t| t.starts_with("音调:"))?
            .strip_prefix("音调:")?,
    );
    if source.is_empty() {
        return None;
    }
    let numbers = "⓪①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳";
    let mut displays = Vec::new();
    let mut spoken = Vec::new();
    for alternative in source.split('、') {
        let mut display_components = Vec::new();
        let mut spoken_components = Vec::new();
        for component in alternative.split('+') {
            let values: Option<Vec<String>> = component
                .chars()
                .map(|c| numbers.chars().position(|v| v == c).map(|n| n.to_string()))
                .collect();
            let values = values?;
            if values.is_empty() {
                return None;
            }
            display_components.push(values.join("/"));
            spoken_components.push(values.join("或"));
        }
        displays.push(display_components.join("+"));
        spoken.push(spoken_components.join("加"));
    }
    Some(Pitch {
        display_text: format!("[{}]", displays.join(", ")),
        accessibility_text: format!("音调型 {}", spoken.join("，或")),
    })
}
pub fn pos_tokens(value: &str) -> Vec<String> {
    let mut result = Vec::new();
    for token in value
        .split('/')
        .map(unicode::trim)
        .filter(|t| !t.is_empty())
    {
        if !result.iter().any(|s| s == token) {
            result.push(token.to_owned());
        }
    }
    result
}
