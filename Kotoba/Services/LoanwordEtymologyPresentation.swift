import Foundation

struct LoanwordEtymologyPresentation: Equatable {
    let title: String
    let value: String

    static func make(for word: VocabularyWord) -> Self? {
        guard let source = word.loanwordSourceTerm?.trimmingCharacters(in: .whitespacesAndNewlines),
              !source.isEmpty else {
            return nil
        }

        let language = languageName(for: word.loanwordSourceLanguageCode)
        let qualifier: String
        if word.loanwordIsWasei {
            qualifier = language == "英语" ? "和制英语" : "和制\(language)"
        } else {
            qualifier = language
        }

        return Self(
            title: word.loanwordIsPartial ? "部分词源" : "外来语词源",
            value: "\(source)（\(qualifier)）"
        )
    }

    private static func languageName(for code: String?) -> String {
        switch code?.lowercased() {
        case "eng", "en": return "英语"
        case "deu", "ger", "de": return "德语"
        case "fra", "fre", "fr": return "法语"
        case "por", "pt": return "葡萄牙语"
        case "nld", "dut", "nl": return "荷兰语"
        case "ita", "it": return "意大利语"
        case "spa", "es": return "西班牙语"
        case "rus", "ru": return "俄语"
        case "kor", "ko": return "韩语"
        case "zho", "chi", "zh": return "汉语"
        default:
            let trimmed = code?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? "其他语言" : trimmed
        }
    }
}
