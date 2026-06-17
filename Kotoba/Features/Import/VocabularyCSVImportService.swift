//
//  VocabularyCSVImportService.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import Foundation
import SwiftData

enum VocabularyDuplicateHandling: String, CaseIterable, Identifiable {
    case skip
    case update

    var id: String { rawValue }

    var title: String {
        switch self {
        case .skip:
            return "跳过重复项"
        case .update:
            return "更新已有单词"
        }
    }
}

enum VocabularyImportTarget: Equatable {
    case newWordBook(name: String, description: String)
    case existingWordBook(UUID)
}

struct VocabularyImportRowError: Error, Identifiable, Equatable {
    let lineNumber: Int
    let reason: String

    var id: String {
        "\(lineNumber)-\(reason)"
    }
}

struct VocabularyImportRow: Identifiable {
    let id = UUID()
    let lineNumber: Int
    let expression: String
    let reading: String
    let meaningChinese: String
    let partOfSpeech: String?
    let exampleJapanese: String?
    let exampleChinese: String?
    let jlptLevel: String?
    let tags: [String]?
    let isDuplicate: Bool

    var key: VocabularyWordImportKey {
        VocabularyWordImportKey(expression: expression, reading: reading)
    }
}

struct VocabularyImportPreview: Identifiable {
    let id = UUID()
    let fileName: String
    let totalRows: Int
    let rows: [VocabularyImportRow]
    let errors: [VocabularyImportRowError]

    var validRows: Int {
        rows.count
    }

    var errorRows: Int {
        errors.count
    }

    var duplicateCount: Int {
        rows.filter(\.isDuplicate).count
    }

    func newCount(for handling: VocabularyDuplicateHandling) -> Int {
        rows.filter { !$0.isDuplicate }.count
    }

    func updateCount(for handling: VocabularyDuplicateHandling) -> Int {
        switch handling {
        case .skip:
            return 0
        case .update:
            return duplicateCount
        }
    }

    func skippedDuplicateCount(for handling: VocabularyDuplicateHandling) -> Int {
        switch handling {
        case .skip:
            return duplicateCount
        case .update:
            return 0
        }
    }
}

struct VocabularyImportResult: Identifiable {
    let id = UUID()
    let insertedCount: Int
    let updatedCount: Int
    let skippedDuplicateCount: Int
    let ignoredErrorCount: Int
    let wordBookID: UUID?
    let wordBookName: String?

    var totalChangedCount: Int {
        insertedCount + updatedCount
    }
}

enum VocabularyCSVImportError: LocalizedError, Equatable {
    case invalidUTF8
    case missingHeaders([String])
    case duplicateHeaders([String])

    var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            return "文件不是有效的 UTF-8 CSV。"
        case .missingHeaders(let headers):
            return "CSV 缺少字段：\(headers.joined(separator: "、"))。"
        case .duplicateHeaders(let headers):
            return "CSV 表头重复：\(headers.joined(separator: "、"))。"
        }
    }
}

struct VocabularyCSVImportService {
    private static let allowedJLPTLevels = Set(["N5", "N4", "N3", "N2", "N1", ""])
    private static let requiredHeaders = [
        "expression",
        "reading",
        "meaningChinese"
    ]

    private let parser = CSVParser()
    private let partOfSpeechTokenizer = PartOfSpeechTokenizer()

    @MainActor
    func makePreview(
        from data: Data,
        fileName: String,
        context: ModelContext,
        targetWordBook: WordBook? = nil,
        createsNewWordBook: Bool = false
    ) throws -> VocabularyImportPreview {
        guard let text = String(data: data, encoding: .utf8) else {
            throw VocabularyCSVImportError.invalidUTF8
        }

        let table = try parser.parse(text)
        let headerIndex = try makeHeaderIndex(from: table.headers)
        let existingKeys = createsNewWordBook ? [] : try fetchExistingKeys(in: context, wordBook: targetWordBook)
        var seenFileKeys: [VocabularyWordImportKey: Int] = [:]
        var rows: [VocabularyImportRow] = []
        var errors: [VocabularyImportRowError] = []

        for record in table.rows {
            let validation = validate(
                record: record,
                headerIndex: headerIndex,
                existingKeys: existingKeys,
                seenFileKeys: seenFileKeys
            )

            switch validation {
            case .success(let row):
                seenFileKeys[row.key] = row.lineNumber
                rows.append(row)
            case .failure(let error):
                errors.append(error)
            }
        }

        return VocabularyImportPreview(
            fileName: fileName,
            totalRows: table.rows.count,
            rows: rows,
            errors: errors
        )
    }

    @MainActor
    func importRows(
        from preview: VocabularyImportPreview,
        duplicateHandling: VocabularyDuplicateHandling,
        context: ModelContext,
        target: VocabularyImportTarget? = nil,
        now: Date = Date()
    ) throws -> VocabularyImportResult {
        let targetWordBook = try resolveImportTarget(target, in: context, now: now)
        let existingWords = try fetchExistingWordsByKey(in: context, wordBook: targetWordBook, treatsNilAsAllWordBooks: target == nil)
        var insertedCount = 0
        var updatedCount = 0
        var skippedDuplicateCount = 0

        do {
            for row in preview.rows {
                if let existingWord = existingWords[row.key] {
                    switch duplicateHandling {
                    case .skip:
                        skippedDuplicateCount += 1
                    case .update:
                        apply(row: row, to: existingWord, now: now)
                        updatedCount += 1
                    }
                } else {
                    let word = makeWord(from: row, wordBook: targetWordBook, now: now)
                    context.insert(word)
                    insertedCount += 1
                }
            }

            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        return VocabularyImportResult(
            insertedCount: insertedCount,
            updatedCount: updatedCount,
            skippedDuplicateCount: skippedDuplicateCount,
            ignoredErrorCount: preview.errorRows,
            wordBookID: targetWordBook?.id,
            wordBookName: targetWordBook?.name
        )
    }

    private func makeHeaderIndex(from headers: [String]) throws -> [String: Int] {
        var headerIndex: [String: Int] = [:]
        var duplicateHeaders: [String] = []

        for (index, header) in headers.enumerated() {
            let name = header.trimmingCharacters(in: .whitespacesAndNewlines)
            if headerIndex[name] != nil {
                duplicateHeaders.append(name)
            } else {
                headerIndex[name] = index
            }
        }

        if !duplicateHeaders.isEmpty {
            throw VocabularyCSVImportError.duplicateHeaders(duplicateHeaders)
        }

        let missingHeaders = Self.requiredHeaders.filter { headerIndex[$0] == nil }
        if !missingHeaders.isEmpty {
            throw VocabularyCSVImportError.missingHeaders(missingHeaders)
        }

        return headerIndex
    }

    private func validate(
        record: CSVRecord,
        headerIndex: [String: Int],
        existingKeys: Set<VocabularyWordImportKey>,
        seenFileKeys: [VocabularyWordImportKey: Int]
    ) -> Result<VocabularyImportRow, VocabularyImportRowError> {
        if record.fields.count > headerIndex.count {
            return .failure(
                VocabularyImportRowError(
                    lineNumber: record.lineNumber,
                    reason: "字段数量多于表头。"
                )
            )
        }

        let expression = value(named: "expression", in: record, using: headerIndex)
        let reading = value(named: "reading", in: record, using: headerIndex)
        let meaningChinese = value(named: "meaningChinese", in: record, using: headerIndex)
        let partOfSpeech = optionalValue(named: "partOfSpeech", in: record, using: headerIndex)
            .map(partOfSpeechTokenizer.normalized)
        let exampleJapanese = optionalValue(named: "exampleJapanese", in: record, using: headerIndex)
        let exampleChinese = optionalValue(named: "exampleChinese", in: record, using: headerIndex)
        let jlptLevel = optionalValue(named: "jlptLevel", in: record, using: headerIndex)
        let tags = optionalValue(named: "tags", in: record, using: headerIndex).map(parseTags)

        var reasons: [String] = []
        if expression.isEmpty {
            reasons.append("expression 必填")
        }

        if reading.isEmpty {
            reasons.append("reading 必填")
        }

        if meaningChinese.isEmpty {
            reasons.append("meaningChinese 必填")
        }

        if let jlptLevel, !Self.allowedJLPTLevels.contains(jlptLevel) {
            reasons.append("jlptLevel 只能为 N5、N4、N3、N2、N1 或空值")
        }

        let key = VocabularyWordImportKey(expression: expression, reading: reading)
        if let firstLineNumber = seenFileKeys[key] {
            reasons.append("与第 \(firstLineNumber) 行的 expression + reading 重复")
        }

        if !reasons.isEmpty {
            return .failure(
                VocabularyImportRowError(
                    lineNumber: record.lineNumber,
                    reason: reasons.joined(separator: "；")
                )
            )
        }

        return .success(
            VocabularyImportRow(
                lineNumber: record.lineNumber,
                expression: expression,
                reading: reading,
                meaningChinese: meaningChinese,
                partOfSpeech: partOfSpeech,
                exampleJapanese: exampleJapanese,
                exampleChinese: exampleChinese,
                jlptLevel: jlptLevel,
                tags: tags,
                isDuplicate: existingKeys.contains(key)
            )
        )
    }

    private func value(named name: String, in record: CSVRecord, using headerIndex: [String: Int]) -> String {
        guard let index = headerIndex[name], record.fields.indices.contains(index) else {
            return ""
        }

        return record.fields[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func optionalValue(named name: String, in record: CSVRecord, using headerIndex: [String: Int]) -> String? {
        guard headerIndex[name] != nil else {
            return nil
        }

        return value(named: name, in: record, using: headerIndex)
    }

    private func parseTags(_ rawValue: String) -> [String] {
        var seenTags = Set<String>()
        var tags: [String] = []

        for tag in rawValue.split(separator: ";", omittingEmptySubsequences: true) {
            let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTag.isEmpty, !seenTags.contains(trimmedTag) else {
                continue
            }

            seenTags.insert(trimmedTag)
            tags.append(trimmedTag)
        }

        return tags
    }

    @MainActor
    private func fetchExistingKeys(in context: ModelContext, wordBook: WordBook?) throws -> Set<VocabularyWordImportKey> {
        let words = try context.fetch(FetchDescriptor<VocabularyWord>())
        return Set(words
            .filter { word in
                guard let wordBook else {
                    return true
                }

                return word.wordBook?.id == wordBook.id
            }
            .map { VocabularyWordImportKey(expression: $0.japanese, reading: $0.kana) })
    }

    @MainActor
    private func fetchExistingWordsByKey(
        in context: ModelContext,
        wordBook: WordBook?,
        treatsNilAsAllWordBooks: Bool
    ) throws -> [VocabularyWordImportKey: VocabularyWord] {
        let words = try context.fetch(FetchDescriptor<VocabularyWord>())
        var wordsByKey: [VocabularyWordImportKey: VocabularyWord] = [:]

        for word in words {
            if let wordBook {
                guard word.wordBook?.id == wordBook.id else {
                    continue
                }
            } else if !treatsNilAsAllWordBooks {
                continue
            }

            let key = VocabularyWordImportKey(expression: word.japanese, reading: word.kana)
            if wordsByKey[key] == nil {
                wordsByKey[key] = word
            }
        }

        return wordsByKey
    }

    private func makeWord(from row: VocabularyImportRow, wordBook: WordBook?, now: Date) -> VocabularyWord {
        let word = VocabularyWord(
            japanese: row.expression,
            kana: row.reading,
            chineseMeaning: row.meaningChinese,
            partOfSpeech: row.partOfSpeech.map(partOfSpeechTokenizer.normalized) ?? "",
            jlptLevel: row.jlptLevel ?? "",
            exampleJapanese: row.exampleJapanese ?? "",
            exampleChinese: row.exampleChinese ?? "",
            tags: row.tags ?? [],
            createdAt: now,
            updatedAt: now,
            wordBook: wordBook
        )
        word.progress = LearningProgress(
            state: .new,
            dueAt: now,
            createdAt: now,
            updatedAt: now,
            word: word
        )

        return word
    }

    @MainActor
    private func resolveImportTarget(
        _ target: VocabularyImportTarget?,
        in context: ModelContext,
        now: Date
    ) throws -> WordBook? {
        guard let target else {
            return nil
        }

        switch target {
        case .newWordBook(let name, let description):
            var draft = WordBookDraft()
            draft.name = name
            draft.bookDescription = description
            let sanitizedDraft = try WordBookService().validateAndSanitize(draft)
            let wordBook = WordBook(
                name: sanitizedDraft.name,
                bookDescription: sanitizedDraft.bookDescription,
                createdAt: now,
                updatedAt: now
            )
            context.insert(wordBook)
            return wordBook
        case .existingWordBook(let id):
            let books = try context.fetch(FetchDescriptor<WordBook>())
            return books.first { $0.id == id }
        }
    }

    private func apply(row: VocabularyImportRow, to word: VocabularyWord, now: Date) {
        word.chineseMeaning = row.meaningChinese
        if let partOfSpeech = row.partOfSpeech {
            word.partOfSpeech = partOfSpeechTokenizer.normalized(partOfSpeech)
        }
        if let exampleJapanese = row.exampleJapanese {
            word.exampleJapanese = exampleJapanese
        }
        if let exampleChinese = row.exampleChinese {
            word.exampleChinese = exampleChinese
        }
        if let jlptLevel = row.jlptLevel {
            word.jlptLevel = jlptLevel
        }
        if let tags = row.tags {
            word.tags = tags
        }
        word.updatedAt = now
    }
}

struct VocabularyWordImportKey: Hashable {
    let expression: String
    let reading: String

    init(expression: String, reading: String) {
        self.expression = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        self.reading = reading.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
