//
//  VocabularyImportQualityService.swift
//  Kotoba
//
//  Created by Codex on 2026/6/18.
//

import Foundation
import SwiftData

enum VocabularyImportQualitySeverity: String, Codable, CaseIterable, Identifiable, Sendable {
    case critical
    case warning
    case info

    var id: String { rawValue }

    var title: String {
        switch self {
        case .critical:
            return "严重错误"
        case .warning:
            return "警告"
        case .info:
            return "提示"
        }
    }
}

struct VocabularyImportQualityIssue: Identifiable, Equatable, Sendable {
    let id: UUID
    let severity: VocabularyImportQualitySeverity
    let lineNumber: Int?
    let expression: String
    let reason: String

    init(
        id: UUID = UUID(),
        severity: VocabularyImportQualitySeverity,
        lineNumber: Int? = nil,
        expression: String = "",
        reason: String
    ) {
        self.id = id
        self.severity = severity
        self.lineNumber = lineNumber
        self.expression = expression
        self.reason = reason
    }
}

struct VocabularyImportQualityReport: Equatable, Sendable {
    let totalRows: Int
    let issues: [VocabularyImportQualityIssue]
    let conjugatableMissingValidDataCount: Int

    var criticalCount: Int { count(.critical) }
    var warningCount: Int { count(.warning) }
    var infoCount: Int { count(.info) }

    var hasIssues: Bool {
        !issues.isEmpty
    }

    func issues(with severity: VocabularyImportQualitySeverity) -> [VocabularyImportQualityIssue] {
        issues.filter { $0.severity == severity }
    }

    func makeCSVReport() -> String {
        let rows = issues.map { issue in
            [
                issue.severity.title,
                issue.lineNumber.map(String.init) ?? "",
                issue.expression,
                issue.reason
            ]
        }

        return makeCSV(
            headers: ["severity", "lineNumber", "expression", "reason"],
            rows: rows
        )
    }

    private func count(_ severity: VocabularyImportQualitySeverity) -> Int {
        issues.filter { $0.severity == severity }.count
    }

    private func makeCSV(headers: [String], rows: [[String]]) -> String {
        ([headers] + rows)
            .map { row in row.map(escapedCSVField).joined(separator: ",") }
            .joined(separator: "\n")
    }

    private func escapedCSVField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else {
            return value
        }

        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

@MainActor
struct VocabularyImportQualityService {
    private let tokenizer = PartOfSpeechTokenizer()
    private let ruleEngine = ConjugationRuleEngine()
    private let knownTagsSeparatorWarning = "tags 使用了中文分号，请改用英文分号 ;。"

    func makeReport(
        preview: VocabularyImportPreview,
        context: ModelContext,
        targetWordBook: WordBook? = nil
    ) throws -> VocabularyImportQualityReport {
        let existingWords = try context.fetch(FetchDescriptor<VocabularyWord>())
        var issues = preview.errors.map { error in
            VocabularyImportQualityIssue(
                severity: .critical,
                lineNumber: error.lineNumber,
                reason: error.reason
            )
        }
        var conjugatableMissingValidDataCount = 0

        for row in preview.rows {
            issues.append(contentsOf: qualityIssues(for: row, existingWords: existingWords, targetWordBook: targetWordBook))

            if needsValidConjugation(row), !canGenerateLocalConjugation(row) {
                conjugatableMissingValidDataCount += 1
            }
        }

        return VocabularyImportQualityReport(
            totalRows: preview.totalRows,
            issues: issues.sorted(by: sortIssues),
            conjugatableMissingValidDataCount: conjugatableMissingValidDataCount
        )
    }

    private func qualityIssues(
        for row: VocabularyImportRow,
        existingWords: [VocabularyWord],
        targetWordBook: WordBook?
    ) -> [VocabularyImportQualityIssue] {
        var issues: [VocabularyImportQualityIssue] = []
        let expression = row.expression
        let reading = row.reading
        let partOfSpeech = row.partOfSpeech ?? ""
        let tokens = tokenizer.tokens(from: partOfSpeech)

        if partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(issue(.warning, row, "partOfSpeech 为空，筛选和活用判断会变弱。"))
        } else if tokens.contains("动词") || tokens.contains("動詞") {
            issues.append(issue(.warning, row, "词性只有“动词”，无法可靠判断一段、五段、サ变或カ变。"))
        } else if tokens.contains("形容词") || tokens.contains("形容詞") {
            issues.append(issue(.warning, row, "词性只有“形容词”，无法可靠判断い形容词或な形容词。"))
        } else if hasUnknownPartOfSpeech(tokens) {
            issues.append(issue(.warning, row, "partOfSpeech 包含无法识别的词性，请确认：\(tokens.joined(separator: "/"))。"))
        }

        if expression == reading {
            issues.append(issue(.info, row, "expression 与 reading 完全相同，适合纯假名词，但请确认不是漏填汉字写法。"))
        }

        if row.isDuplicate {
            issues.append(issue(.warning, row, "当前导入目标中已存在相同 expression + reading。"))
        }

        if hasDuplicateInOtherWordBook(row, existingWords: existingWords, targetWordBook: targetWordBook) {
            issues.append(issue(.info, row, "其他词书中存在同名单词，请确认是否需要合并。"))
        }

        if needsValidConjugation(row), !canGenerateLocalConjugation(row) {
            issues.append(issue(.warning, row, "可活用词缺少明确活用类型，无法生成可信本地活用。"))
        }

        if (row.tags ?? []).contains(where: { $0.contains("；") }) {
            issues.append(issue(.warning, row, knownTagsSeparatorWarning))
        }

        if !isKanaReading(reading) {
            issues.append(issue(.warning, row, "reading 中包含非假名字符，请确认假名读音。"))
        }

        let exampleJapanese = row.exampleJapanese ?? ""
        if exampleJapanese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(issue(.info, row, "缺少日语例句。"))
        } else if !exampleJapanese.contains(expression) {
            issues.append(issue(.info, row, "日语例句中未直接包含 expression。"))
        }

        if (row.exampleChinese ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(issue(.info, row, "缺少中文例句翻译。"))
        }

        if isNaAdjectiveRisk(expression: expression, reading: reading, tokens: tokens) {
            issues.append(issue(.warning, row, "\(expression) 以 い 结尾，但常见为な形容词，请确认词性。"))
        }

        return issues
    }

    private func issue(
        _ severity: VocabularyImportQualitySeverity,
        _ row: VocabularyImportRow,
        _ reason: String
    ) -> VocabularyImportQualityIssue {
        VocabularyImportQualityIssue(
            severity: severity,
            lineNumber: row.lineNumber,
            expression: row.expression,
            reason: reason
        )
    }

    private func hasDuplicateInOtherWordBook(
        _ row: VocabularyImportRow,
        existingWords: [VocabularyWord],
        targetWordBook: WordBook?
    ) -> Bool {
        existingWords.contains { word in
            word.japanese == row.expression
                && word.kana == row.reading
                && word.wordBook?.id != targetWordBook?.id
        }
    }

    private func needsValidConjugation(_ row: VocabularyImportRow) -> Bool {
        let tokens = tokenizer.tokens(from: row.partOfSpeech ?? "")
        let conjugatableTokens: Set<String> = [
            "动词", "動詞", "一段动词", "一段動詞", "五段动词", "五段動詞",
            "サ变动词", "サ変動詞", "する动词", "する動詞", "カ变动词", "カ変動詞",
            "形容词", "形容詞", "い形容词", "い形容詞", "な形容词", "な形容詞"
        ]
        return tokens.contains { conjugatableTokens.contains($0) }
    }

    private func canGenerateLocalConjugation(_ row: VocabularyImportRow) -> Bool {
        let word = makePreviewWord(row)
        return ruleEngine.generate(for: word) != nil
    }

    private func makePreviewWord(_ row: VocabularyImportRow) -> VocabularyWord {
        VocabularyWord(
            japanese: row.expression,
            kana: row.reading,
            chineseMeaning: row.meaningChinese,
            partOfSpeech: row.partOfSpeech ?? "",
            jlptLevel: row.jlptLevel ?? ""
        )
    }

    private func hasUnknownPartOfSpeech(_ tokens: [String]) -> Bool {
        let knownTokens: Set<String> = [
            "名词", "名詞", "动词", "動詞", "一段动词", "一段動詞", "五段动词", "五段動詞",
            "サ变动词", "サ変動詞", "する动词", "する動詞", "カ变动词", "カ変動詞",
            "い形容词", "い形容詞", "な形容词", "な形容詞", "形容词", "形容詞",
            "副词", "副詞", "助词", "助詞", "感叹词", "感動詞", "连体词", "連体詞"
        ]

        return tokens.contains { !knownTokens.contains($0) }
    }

    private func isKanaReading(_ reading: String) -> Bool {
        let trimmed = reading.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }

        return trimmed.unicodeScalars.allSatisfy { scalar in
            (0x3041...0x3096).contains(Int(scalar.value))
                || (0x30A1...0x30F6).contains(Int(scalar.value))
                || scalar.value == 0x30FC
        }
    }

    private func isNaAdjectiveRisk(expression: String, reading: String, tokens: [String]) -> Bool {
        let riskyWords = Set(["きれい", "綺麗", "嫌い", "きらい", "有名", "ゆうめい"])
        guard tokens.contains("い形容词") || tokens.contains("い形容詞") else {
            return false
        }

        return riskyWords.contains(expression) || riskyWords.contains(reading)
    }

    private func sortIssues(_ lhs: VocabularyImportQualityIssue, _ rhs: VocabularyImportQualityIssue) -> Bool {
        let severityOrder: [VocabularyImportQualitySeverity: Int] = [.critical: 0, .warning: 1, .info: 2]
        let lhsOrder = severityOrder[lhs.severity] ?? 9
        let rhsOrder = severityOrder[rhs.severity] ?? 9
        if lhsOrder != rhsOrder {
            return lhsOrder < rhsOrder
        }

        return (lhs.lineNumber ?? Int.max) < (rhs.lineNumber ?? Int.max)
    }
}
