import Foundation

enum AttributionCategory: String, Equatable {
    case builtInVocabulary
    case loanwordEtymology
}

struct DataSourceAttribution: Identifiable, Equatable {
    let id: String
    let category: AttributionCategory
    let shortName: String
    let fullName: String
    let url: URL
    let modificationNote: String
    let licenseName: String?
    let notice: String
}

enum AppAttribution {
    static let builtInVocabulary = DataSourceAttribution(
        id: "egg-rolls-jlpt",
        category: .builtInVocabulary,
        shortName: "egg rolls",
        fullName: "egg rolls / anki-jlpt-decks",
        url: trustedURL("https://github.com/5mdld/anki-jlpt-decks"),
        modificationNote: "基于原始数据整理与修改",
        licenseName: "CC BY-NC 4.0",
        notice: "Kotoba 的 JLPT 内置词书、音调标记及外来语原型字段来源于 egg rolls 制作的 anki-jlpt-decks。"
    )

    static let loanwordEtymology = DataSourceAttribution(
        id: "jmdict-loanword-etymology",
        category: .loanwordEtymology,
        shortName: "JMdict",
        fullName: "JMdict（Electronic Dictionary Research and Development Group）",
        url: trustedURL("https://www.edrdg.org/jmdict/j_jmdict.html"),
        modificationNote: "作为 egg rolls 外来语原型字段的补充，按单词与读音保守匹配后整理为词源 sidecar",
        licenseName: "CC BY-SA 4.0",
        notice: "仅使用 JMdict 中能够可靠匹配的补充来源与词源标记；完整声明保留于 JMdict_NOTICE.txt。"
    )

    static let all: [DataSourceAttribution] = [builtInVocabulary, loanwordEtymology]

    private static func trustedURL(_ value: String) -> URL {
        guard let url = URL(string: value) else {
            preconditionFailure("Invalid bundled attribution URL: \(value)")
        }
        return url
    }
}

struct AppVersionInfo: Equatable {
    let version: String
    let build: String

    var displayText: String { "版本 \(version)（构建 \(build)）" }

    static var current: AppVersionInfo {
        make(infoDictionary: Bundle.main.infoDictionary)
    }

    static func make(infoDictionary: [String: Any]?) -> AppVersionInfo {
        AppVersionInfo(
            version: normalizedValue(infoDictionary?["CFBundleShortVersionString"]),
            build: normalizedValue(infoDictionary?["CFBundleVersion"])
        )
    }

    private static func normalizedValue(_ value: Any?) -> String {
        guard let string = value as? String,
              !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "—"
        }
        return string
    }
}
