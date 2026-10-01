import Foundation

enum JapaneseRomajiFormatter {
    private static let syllables: [String: String] = [
        "あ": "a", "い": "i", "う": "u", "え": "e", "お": "o",
        "か": "ka", "き": "ki", "く": "ku", "け": "ke", "こ": "ko",
        "さ": "sa", "し": "shi", "す": "su", "せ": "se", "そ": "so",
        "た": "ta", "ち": "chi", "つ": "tsu", "て": "te", "と": "to",
        "な": "na", "に": "ni", "ぬ": "nu", "ね": "ne", "の": "no",
        "は": "ha", "ひ": "hi", "ふ": "fu", "へ": "he", "ほ": "ho",
        "ま": "ma", "み": "mi", "む": "mu", "め": "me", "も": "mo",
        "や": "ya", "ゆ": "yu", "よ": "yo",
        "ら": "ra", "り": "ri", "る": "ru", "れ": "re", "ろ": "ro",
        "わ": "wa", "ゐ": "wi", "ゑ": "we", "を": "o", "ん": "n",
        "が": "ga", "ぎ": "gi", "ぐ": "gu", "げ": "ge", "ご": "go",
        "ざ": "za", "じ": "ji", "ず": "zu", "ぜ": "ze", "ぞ": "zo",
        "だ": "da", "ぢ": "ji", "づ": "zu", "で": "de", "ど": "do",
        "ば": "ba", "び": "bi", "ぶ": "bu", "べ": "be", "ぼ": "bo",
        "ぱ": "pa", "ぴ": "pi", "ぷ": "pu", "ぺ": "pe", "ぽ": "po",
        "ゔ": "vu", "ぁ": "a", "ぃ": "i", "ぅ": "u", "ぇ": "e", "ぉ": "o",
        "ゎ": "wa"
    ]

    private static let combinations: [String: String] = [
        "きゃ": "kya", "きゅ": "kyu", "きょ": "kyo",
        "ぎゃ": "gya", "ぎゅ": "gyu", "ぎょ": "gyo",
        "しゃ": "sha", "しゅ": "shu", "しょ": "sho", "しぇ": "she",
        "じゃ": "ja", "じゅ": "ju", "じょ": "jo", "じぇ": "je",
        "ちゃ": "cha", "ちゅ": "chu", "ちょ": "cho", "ちぇ": "che",
        "にゃ": "nya", "にゅ": "nyu", "にょ": "nyo",
        "ひゃ": "hya", "ひゅ": "hyu", "ひょ": "hyo",
        "びゃ": "bya", "びゅ": "byu", "びょ": "byo",
        "ぴゃ": "pya", "ぴゅ": "pyu", "ぴょ": "pyo",
        "みゃ": "mya", "みゅ": "myu", "みょ": "myo",
        "りゃ": "rya", "りゅ": "ryu", "りょ": "ryo",
        "いぇ": "ye", "うぃ": "wi", "うぇ": "we", "うぉ": "wo",
        "ゔぁ": "va", "ゔぃ": "vi", "ゔぇ": "ve", "ゔぉ": "vo", "ゔゅ": "vyu",
        "くぁ": "kwa", "くぃ": "kwi", "くぇ": "kwe", "くぉ": "kwo",
        "ぐぁ": "gwa", "ぐぃ": "gwi", "ぐぇ": "gwe", "ぐぉ": "gwo",
        "すぃ": "si", "ずぃ": "zi", "てぃ": "ti", "でぃ": "di",
        "てゅ": "tyu", "でゅ": "dyu", "とぅ": "tu", "どぅ": "du",
        "つぁ": "tsa", "つぃ": "tsi", "つぇ": "tse", "つぉ": "tso",
        "ふぁ": "fa", "ふぃ": "fi", "ふぇ": "fe", "ふぉ": "fo", "ふゅ": "fyu"
    ]

    static func string(from reading: String) -> String {
        let kana = hiragana(from: reading.precomposedStringWithCanonicalMapping)
        let characters = Array(kana)
        var raw = ""
        var index = 0
        var geminatesNext = false

        while index < characters.count {
            let character = characters[index]
            if character == "っ" {
                geminatesNext = true
                index += 1
                continue
            }

            if character == "ー" {
                raw = lengtheningLastVowel(in: raw)
                index += 1
                continue
            }

            let pair = index + 1 < characters.count ? String([character, characters[index + 1]]) : ""
            let romanized: String
            if character == "ん" {
                let nextCharacter = index + 1 < characters.count ? characters[index + 1] : nil
                romanized = requiresApostrophe(afterSyllabicNBefore: nextCharacter) ? "n'" : "n"
                index += 1
            } else if let combination = combinations[pair] {
                romanized = combination
                index += 2
            } else if let syllable = syllables[String(character)] {
                romanized = syllable
                index += 1
            } else {
                raw.append(character)
                index += 1
                geminatesNext = false
                continue
            }

            if geminatesNext {
                raw += geminatedPrefix(for: romanized)
                geminatesNext = false
            }
            raw += romanized
        }

        return applyingHepburnLongVowels(to: raw)
    }

    private static func hiragana(from value: String) -> String {
        String(value.unicodeScalars.map { scalar -> Character in
            let code = scalar.value
            if (0x30A1...0x30F6).contains(code), let converted = UnicodeScalar(code - 0x60) {
                return Character(String(converted))
            }
            return Character(String(scalar))
        })
    }

    private static func geminatedPrefix(for value: String) -> String {
        if value.hasPrefix("ch") { return "t" }
        guard let first = value.first, !"aeioun".contains(first) else { return "" }
        return String(first)
    }

    private static func requiresApostrophe(afterSyllabicNBefore nextCharacter: Character?) -> Bool {
        guard let nextCharacter else { return false }
        return "あいうえおやゆよぁぃぅぇぉゃゅょ".contains(nextCharacter)
    }

    private static func applyingHepburnLongVowels(to value: String) -> String {
        value
            .replacingOccurrences(of: "aa", with: "ā")
            .replacingOccurrences(of: "ii", with: "ī")
            .replacingOccurrences(of: "uu", with: "ū")
            .replacingOccurrences(of: "ee", with: "ē")
            .replacingOccurrences(of: "oo", with: "ō")
            .replacingOccurrences(of: "ou", with: "ō")
    }

    private static func lengtheningLastVowel(in value: String) -> String {
        guard let index = value.lastIndex(where: { "aeiouāīūēō".contains($0) }) else { return value }
        let replacement: Character
        switch value[index] {
        case "a", "ā": replacement = "ā"
        case "i", "ī": replacement = "ī"
        case "u", "ū": replacement = "ū"
        case "e", "ē": replacement = "ē"
        case "o", "ō": replacement = "ō"
        default: return value
        }
        var result = value
        result.replaceSubrange(index...index, with: String(replacement))
        return result
    }
}
