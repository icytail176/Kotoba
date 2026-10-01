import Foundation

enum LoanwordEtymologyDisplayPolicy {
    enum NormalizedLanguage: String, CaseIterable {
        case english
        case german
        case french
        case dutch
        case portuguese
        case italian
        case spanish
        case russian
        case latin
        case chinese

        var localizedName: String {
            switch self {
            case .english: "英语"
            case .german: "德语"
            case .french: "法语"
            case .dutch: "荷兰语"
            case .portuguese: "葡萄牙语"
            case .italian: "意大利语"
            case .spanish: "西班牙语"
            case .russian: "俄语"
            case .latin: "拉丁语"
            case .chinese: "汉语"
            }
        }
    }

    static func normalizedLanguage(for rawValue: String?) -> NormalizedLanguage? {
        let value = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        switch value {
        case "eng", "en": return .english
        case "deu", "ger", "de": return .german
        case "fra", "fre", "fr": return .french
        case "nld", "dut", "nl": return .dutch
        case "por", "pt": return .portuguese
        case "ita", "it": return .italian
        case "spa", "es": return .spanish
        case "rus", "ru": return .russian
        case "lat", "la": return .latin
        case "zho", "chi", "zh", "chinese", "chinese-origin", "sino", "sino-origin",
             "中文", "汉语", "漢語", "中国語":
            return .chinese
        default: return nil
        }
    }

    static func localizedLanguageName(for rawValue: String?) -> String? {
        normalizedLanguage(for: rawValue)?.localizedName
    }

    static func shouldDisplay(
        sourceTerm: String?,
        sourceLanguage: String?,
        isWasei: Bool,
        isPartial: Bool
    ) -> Bool {
        guard let sourceTerm,
              !sourceTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard let language = normalizedLanguage(for: sourceLanguage) else {
            // Wasei metadata is itself an explicit modern mnemonic. Other
            // missing/unknown language values stay hidden until classified.
            return isWasei
        }
        // Chinese/Sino exclusion wins even for partial-source metadata.
        if language == .chinese { return false }
        return true
    }
}

struct LoanwordEtymologyPresentation: Equatable {
    let title: String
    let sourceTerm: String
    let sourceLanguageName: String?
    let isWasei: Bool
    let isPartial: Bool
    let value: String

    var accessibilityValue: String {
        let kind = isPartial ? "部分词源" : "词源"
        let spokenSource: String
        if isWasei {
            spokenSource = sourceLanguageName == "英语"
                ? "和制英语 \(sourceTerm)"
                : "和制词 \(sourceTerm)"
        } else if let sourceLanguageName {
            spokenSource = "\(sourceLanguageName) \(sourceTerm)"
        } else {
            spokenSource = sourceTerm
        }
        return "\(kind)，\(spokenSource)"
    }

    var inlineValue: String {
        isPartial ? "\(value) · 部分词源" : value
    }

    static func make(for word: VocabularyWord) -> Self? {
        guard let source = word.loanwordSourceTerm?.trimmingCharacters(in: .whitespacesAndNewlines),
              !source.isEmpty,
              LoanwordEtymologyDisplayPolicy.shouldDisplay(
                sourceTerm: source,
                sourceLanguage: word.loanwordSourceLanguageCode,
                isWasei: word.loanwordIsWasei,
                isPartial: word.loanwordIsPartial
              ) else {
            return nil
        }

        let language = LoanwordEtymologyDisplayPolicy.localizedLanguageName(
            for: word.loanwordSourceLanguageCode
        )
        let qualifier: String?
        if word.loanwordIsWasei {
            if let language, language != "英语" {
                qualifier = "和制\(language)"
            } else {
                qualifier = "和制英语"
            }
        } else {
            qualifier = language
        }

        let value = qualifier.map { "\(source)（\($0)）" } ?? source

        return Self(
            title: word.loanwordIsPartial ? "部分词源" : "外来语词源",
            sourceTerm: source,
            sourceLanguageName: language,
            isWasei: word.loanwordIsWasei,
            isPartial: word.loanwordIsPartial,
            value: value
        )
    }
}

struct StudyCardMeaningPresentation: Equatable {
    let meaning: String
    let sourceMetadata: String?
    let accessibilityText: String

    var inlineText: String {
        [meaning, sourceMetadata]
            .compactMap { value in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: " · ")
    }

    static func make(for item: StudySession.Item) -> Self {
        make(for: item.word)
    }

    static func make(for word: VocabularyWord) -> Self {
        let meaning = word.chineseMeaning.trimmingCharacters(in: .whitespacesAndNewlines)
        let etymology = LoanwordEtymologyPresentation.make(for: word)
        let accessibilityComponents = [
            meaning.isEmpty ? nil : "释义，\(meaning)",
            etymology?.accessibilityValue
        ].compactMap { $0 }
        return Self(
            meaning: meaning,
            sourceMetadata: etymology?.inlineValue,
            accessibilityText: accessibilityComponents.joined(separator: "。")
        )
    }
}
