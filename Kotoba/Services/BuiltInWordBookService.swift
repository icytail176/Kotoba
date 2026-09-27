//
//  BuiltInWordBookService.swift
//  Kotoba
//
//  Loads the five bundled JLPT word books. The sample CSV is deliberately
//  not part of this manifest: it is only a format reference for manual import.
//

import Foundation
import SwiftData

struct BuiltInWordBookDefinition: Equatable, Sendable {
    let level: String
    let displayName: String
    let fileName: String
    let expectedWordCount: Int?

    init(
        level: String,
        displayName: String,
        fileName: String,
        expectedWordCount: Int? = nil
    ) {
        self.level = level
        self.displayName = displayName
        self.fileName = fileName
        self.expectedWordCount = expectedWordCount
    }

    nonisolated static let all = [
        BuiltInWordBookDefinition(level: "N5", displayName: "JLPT N5", fileName: "eggrolls_kotoba_N5_strict.csv", expectedWordCount: 802),
        BuiltInWordBookDefinition(level: "N4", displayName: "JLPT N4", fileName: "eggrolls_kotoba_N4_strict.csv", expectedWordCount: 755),
        BuiltInWordBookDefinition(level: "N3", displayName: "JLPT N3", fileName: "eggrolls_kotoba_N3_strict.csv", expectedWordCount: 1_817),
        BuiltInWordBookDefinition(level: "N2", displayName: "JLPT N2", fileName: "eggrolls_kotoba_N2_strict.csv", expectedWordCount: 3_206),
        BuiltInWordBookDefinition(level: "N1", displayName: "JLPT N1", fileName: "eggrolls_kotoba_N1_strict.csv", expectedWordCount: 4_029)
    ]
}

struct BuiltInWordBookLoadResult: Equatable {
    let level: String
    let displayName: String
    let wordCount: Int
    let importedWordCount: Int
}

struct BuiltInWordBookFieldCorrection: Equatable, Sendable {
    let level: String
    let expression: String
    let reading: String
    let oldPartOfSpeech: String
    let newPartOfSpeech: String
}

struct BuiltInLoanwordEtymology: Equatable, Sendable {
    let wordBook: String
    let expression: String
    let reading: String
    let sourceTerm: String
    let sourceLanguageCode: String
    let isWasei: Bool
    let isPartial: Bool
}

enum BuiltInWordBookError: LocalizedError, Equatable {
    case resourceNotFound(String)
    case invalidUTF8(String)
    case invalidHeaders(fileName: String, actual: [String])
    case invalidColumnCount(fileName: String, line: Int, actual: Int)
    case missingRequiredValue(fileName: String, line: Int, field: String)
    case mismatchedJLPTLevel(fileName: String, line: Int, actual: String, expected: String)
    case invalidPartOfSpeech(fileName: String, line: Int)
    case invalidTagSeparator(fileName: String, line: Int)
    case duplicateVocabulary(fileName: String, line: Int)
    case prohibitedContent(fileName: String, line: Int)
    case invalidEtymologyHeaders(actual: [String])
    case invalidEtymologyRow(line: Int, reason: String)
    case incompleteSeed

    var errorDescription: String? {
        switch self {
        case .resourceNotFound(let fileName):
            return "找不到内置词书资源：\(fileName)。"
        case .invalidUTF8(let fileName):
            return "内置词书不是有效的 UTF-8 文件：\(fileName)。"
        case .invalidHeaders(let fileName, _):
            return "内置词书表头不符合规定：\(fileName)。"
        case .invalidColumnCount(let fileName, let line, let actual):
            return "内置词书 \(fileName) 第 \(line) 行有 \(actual) 列，应为 8 列。"
        case .missingRequiredValue(let fileName, let line, let field):
            return "内置词书 \(fileName) 第 \(line) 行的 \(field) 不能为空。"
        case .mismatchedJLPTLevel(let fileName, let line, let actual, let expected):
            return "内置词书 \(fileName) 第 \(line) 行的 jlptLevel 为 \(actual)，应为 \(expected)。"
        case .invalidPartOfSpeech(let fileName, let line):
            return "内置词书 \(fileName) 第 \(line) 行的 partOfSpeech 必须使用 / 分隔。"
        case .invalidTagSeparator(let fileName, let line):
            return "内置词书 \(fileName) 第 \(line) 行的 tags 必须使用英文分号分隔。"
        case .duplicateVocabulary(let fileName, let line):
            return "内置词书 \(fileName) 第 \(line) 行与前面的 expression 和 reading 重复。"
        case .prohibitedContent(let fileName, let line):
            return "内置词书 \(fileName) 第 \(line) 行包含 HTML 或 Anki 音频标记。"
        case .invalidEtymologyHeaders:
            return "内置外来语词源资源表头不符合规定。"
        case .invalidEtymologyRow(let line, let reason):
            return "内置外来语词源资源第 \(line) 行无效：\(reason)"
        case .incompleteSeed:
            return "内置词书初始化未完成，将在下次启动时重试。"
        }
    }
}

@MainActor
struct BuiltInWordBookService {
    typealias PhaseRecorder = (_ phase: String, _ elapsed: Duration) -> Void

    static let builtInVocabularyVersion = 6

    nonisolated static let conjugationAuditCorrections = [
        BuiltInWordBookFieldCorrection(
            level: "N5",
            expression: "来る",
            reading: "くる",
            oldPartOfSpeech: "サ变动词/补助动词",
            newPartOfSpeech: "动词/自动词/カ变动词/补助动词"
        ),
        BuiltInWordBookFieldCorrection(
            level: "N2",
            expression: "やってくる",
            reading: "やってくる",
            oldPartOfSpeech: "サ变动词",
            newPartOfSpeech: "动词/自动词/カ变动词"
        ),
        BuiltInWordBookFieldCorrection(
            level: "N2",
            expression: "買い与える",
            reading: "かいあたえる",
            oldPartOfSpeech: "动词/他动词/五段动词",
            newPartOfSpeech: "动词/他动词/一段动词"
        ),
        BuiltInWordBookFieldCorrection(
            level: "N1",
            expression: "擦り抜ける",
            reading: "すりぬける",
            oldPartOfSpeech: "动词/自动词/五段动词",
            newPartOfSpeech: "动词/自动词/一段动词"
        ),
        BuiltInWordBookFieldCorrection(
            level: "N1",
            expression: "生まれ落ちる",
            reading: "うまれおちる",
            oldPartOfSpeech: "动词/自动词/五段动词",
            newPartOfSpeech: "动词/自动词/一段动词"
        )
    ]

    static let requiredHeaders = [
        "expression",
        "reading",
        "meaningChinese",
        "partOfSpeech",
        "exampleJapanese",
        "exampleChinese",
        "jlptLevel",
        "tags"
    ]

    static let etymologyHeaders = [
        "wordBook",
        "expression",
        "reading",
        "sourceTerm",
        "sourceLanguage",
        "isWasei",
        "isPartial"
    ]

    private let definitions: [BuiltInWordBookDefinition]
    private let dataProvider: (BuiltInWordBookDefinition) throws -> Data
    private let etymologyDataProvider: () throws -> Data?
    private let userDefaults: UserDefaults
    private let phaseRecorder: PhaseRecorder?
    private let parser = CSVParser()
    private let partOfSpeechTokenizer = PartOfSpeechTokenizer()

    init(
        definitions: [BuiltInWordBookDefinition] = BuiltInWordBookDefinition.all,
        bundle: Bundle = .main,
        userDefaults: UserDefaults = .standard,
        phaseRecorder: PhaseRecorder? = nil
    ) {
        self.definitions = definitions
        self.userDefaults = userDefaults
        self.phaseRecorder = phaseRecorder
        self.dataProvider = { definition in
            let url = Self.resourceURL(for: definition, in: bundle)
            #if DEBUG
            print("[BuiltInWordBook] Bundle resource lookup:", definition.fileName, url?.path ?? "nil")
            #endif
            guard let url else {
                throw BuiltInWordBookError.resourceNotFound(definition.fileName)
            }
            return try Data(contentsOf: url)
        }
        self.etymologyDataProvider = {
            let url = bundle.url(forResource: "builtin_loanword_etymology", withExtension: "csv")
                ?? bundle.url(forResource: "builtin_loanword_etymology", withExtension: "csv", subdirectory: "Resources")
            guard let url else { throw BuiltInWordBookError.resourceNotFound("builtin_loanword_etymology.csv") }
            return try Data(contentsOf: url)
        }
    }

    init(
        definitions: [BuiltInWordBookDefinition] = BuiltInWordBookDefinition.all,
        dataProvider: @escaping (BuiltInWordBookDefinition) throws -> Data,
        etymologyDataProvider: @escaping () throws -> Data? = { nil },
        userDefaults: UserDefaults = .standard,
        phaseRecorder: PhaseRecorder? = nil
    ) {
        self.definitions = definitions
        self.dataProvider = dataProvider
        self.etymologyDataProvider = etymologyDataProvider
        self.userDefaults = userDefaults
        self.phaseRecorder = phaseRecorder
    }

    /// Validates every bundled source before changing persistent data, then
    /// creates missing books or incrementally refreshes an older built-in
    /// version while keeping progress for words whose expression and reading
    /// still match.
    @discardableResult
    func loadIfNeeded(in context: ModelContext, now: Date = Date()) throws -> [BuiltInWordBookLoadResult] {
        try measurePhase("total") {
            let existingBooks = try measurePhase("existing books fetch") {
                try context.fetch(FetchDescriptor<WordBook>())
            }
            let storedSeedVersion = userDefaults.integer(forKey: AppSettings.builtInWordBookSeedVersionKey)

            if storedSeedVersion == Self.builtInVocabularyVersion,
               let existingCounts = try measurePhase("fast-path integrity counts", operation: {
                   try currentSeedWordCounts(in: context, books: existingBooks)
               }) {
                return loadResults(wordCounts: existingCounts, importedCounts: [:])
            }

            let existingCounts = try measurePhase("existing word counts") {
                try builtInWordCounts(in: context, books: existingBooks)
            }

            let needsIntegrityRepair = existingCounts == nil
            let repairsReadingNormalizationDuplicates = storedSeedVersion == 2 || storedSeedVersion < Self.builtInVocabularyVersion
            let appliesConjugationAuditFieldPatch = storedSeedVersion == 4 && !needsIntegrityRepair

            #if DEBUG
            print(
                "[BuiltInWordBook] Seed status:",
                "storedVersion=\(storedSeedVersion)",
                "targetVersion=\(Self.builtInVocabularyVersion)",
                "needsIntegrityRepair=\(needsIntegrityRepair)",
                "repairsReadingNormalizationDuplicates=\(repairsReadingNormalizationDuplicates)"
            )
            #endif

            let parsedBooks = try definitions.map { definition in
                (definition, try rows(for: definition))
            }
            let etymologies = try etymologyRows()
            var importedCounts: [String: Int] = [:]

            measurePhase("SwiftData insert/update") {
                for (offset, parsedBook) in parsedBooks.enumerated() {
                    let definition = parsedBook.0
                    let rows = parsedBook.1
                    if let existingBook = existingBooks.first(where: { $0.isBuiltIn && $0.name == definition.displayName }) {
                        if appliesConjugationAuditFieldPatch {
                            applyConjugationAuditCorrections(
                                to: existingBook,
                                level: definition.level,
                                now: now
                            )
                            importedCounts[definition.level] = 0
                        } else {
                            importedCounts[definition.level] = refresh(
                                existingBook,
                                from: rows,
                                in: context,
                                now: now,
                                repairsReadingNormalizationDuplicates: repairsReadingNormalizationDuplicates
                            )
                        }
                        existingBook.updatedAt = now
                        continue
                    }

                    let wordBook = WordBook(
                        name: definition.displayName,
                        bookDescription: "内置 \(definition.displayName) 词书。",
                        createdAt: now.addingTimeInterval(TimeInterval(offset)),
                        updatedAt: now.addingTimeInterval(TimeInterval(offset)),
                        isBuiltIn: true
                    )
                    context.insert(wordBook)

                    for row in rows {
                        context.insert(makeWord(from: row, wordBook: wordBook, now: now))
                    }
                    importedCounts[definition.level] = rows.count
                }
            }

            let refreshedBooks = try measurePhase("post-mutation books fetch") {
                try context.fetch(FetchDescriptor<WordBook>())
            }
            measurePhase("sidecar apply") {
                applyEtymologies(etymologies, to: refreshedBooks, now: now)
            }

            if context.hasChanges {
                do {
                    try measurePhase("ModelContext save") {
                        try context.save()
                    }
                } catch {
                    context.rollback()
                    throw error
                }
            }

            try measurePhase("final integrity validation") {
                let savedBooks = try context.fetch(FetchDescriptor<WordBook>())
                guard try builtInWordCounts(in: context, books: savedBooks) != nil else {
                    throw BuiltInWordBookError.incompleteSeed
                }
            }
            userDefaults.set(Self.builtInVocabularyVersion, forKey: AppSettings.builtInWordBookSeedVersionKey)

            let parsedCounts = Dictionary(
                uniqueKeysWithValues: parsedBooks.map { definition, rows in
                    (definition.level, rows.count)
                }
            )
            return loadResults(wordCounts: parsedCounts, importedCounts: importedCounts)
        }
    }

    /// Cheap current-version integrity gate. It counts active rows directly in
    /// the store and does not parse or materialize the bundled CSV resources.
    private func currentSeedWordCounts(
        in context: ModelContext,
        books: [WordBook]
    ) throws -> [String: Int]? {
        var counts: [String: Int] = [:]

        for definition in definitions {
            guard let book = books.first(where: { $0.isBuiltIn && $0.name == definition.displayName }) else {
                return nil
            }
            let bookID = book.id
            let descriptor = FetchDescriptor<VocabularyWord>(predicate: #Predicate { word in
                word.wordBook?.id == bookID && !word.isArchived
            })
            let actualCount = try context.fetchCount(descriptor)
            if let expectedWordCount = definition.expectedWordCount {
                guard actualCount == expectedWordCount else { return nil }
            } else {
                guard actualCount > 0 else { return nil }
            }
            counts[definition.level] = actualCount
        }

        return counts
    }

    private func rows(for definition: BuiltInWordBookDefinition) throws -> [CSVRecord] {
        let data = try measurePhase("resource file read") {
            try dataProvider(definition)
        }
        let text = try measurePhase("Data/String decode") {
            guard let text = String(data: data, encoding: .utf8) else {
                throw BuiltInWordBookError.invalidUTF8(definition.fileName)
            }
            return text
        }

        let table = try measurePhase("CSV parse") {
            try parser.parse(text)
        }
        try measurePhase("manifest validation") {
            guard table.headers == Self.requiredHeaders else {
                throw BuiltInWordBookError.invalidHeaders(fileName: definition.fileName, actual: table.headers)
            }
        }

        try measurePhase("CSV validation and identity keys") {
            var vocabularyKeys = Set<VocabularyWordImportKey>()
            for record in table.rows {
                guard record.fields.count == Self.requiredHeaders.count else {
                    throw BuiltInWordBookError.invalidColumnCount(
                        fileName: definition.fileName,
                        line: record.lineNumber,
                        actual: record.fields.count
                    )
                }

                for (index, fieldName) in [(0, "expression"), (1, "reading"), (2, "meaningChinese"), (6, "jlptLevel")] {
                    guard !record.fields[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw BuiltInWordBookError.missingRequiredValue(
                            fileName: definition.fileName,
                            line: record.lineNumber,
                            field: fieldName
                        )
                    }
                }

                let level = record.fields[6].trimmingCharacters(in: .whitespacesAndNewlines)
                guard level == definition.level else {
                    throw BuiltInWordBookError.mismatchedJLPTLevel(
                        fileName: definition.fileName,
                        line: record.lineNumber,
                        actual: level,
                        expected: definition.level
                    )
                }

                let partOfSpeech = record.fields[3].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !partOfSpeech.contains("；"), !partOfSpeech.contains(";") else {
                    throw BuiltInWordBookError.invalidPartOfSpeech(fileName: definition.fileName, line: record.lineNumber)
                }

                let tags = record.fields[7].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !tags.contains("；") else {
                    throw BuiltInWordBookError.invalidTagSeparator(fileName: definition.fileName, line: record.lineNumber)
                }

                let key = VocabularyWordImportKey(expression: record.fields[0], reading: record.fields[1])
                guard vocabularyKeys.insert(key).inserted else {
                    throw BuiltInWordBookError.duplicateVocabulary(fileName: definition.fileName, line: record.lineNumber)
                }

                guard !record.fields.contains(where: containsProhibitedContent) else {
                    throw BuiltInWordBookError.prohibitedContent(fileName: definition.fileName, line: record.lineNumber)
                }
            }
        }

        return table.rows
    }

    private func etymologyRows() throws -> [BuiltInLoanwordEtymology] {
        guard let data = try measurePhase("sidecar file read", operation: etymologyDataProvider) else { return [] }
        let text = try measurePhase("sidecar Data/String decode") {
            guard let text = String(data: data, encoding: .utf8) else {
                throw BuiltInWordBookError.invalidUTF8("builtin_loanword_etymology.csv")
            }
            return text
        }
        let table = try measurePhase("sidecar parse") {
            try parser.parse(text)
        }
        try measurePhase("sidecar manifest validation") {
            guard table.headers == Self.etymologyHeaders else {
                throw BuiltInWordBookError.invalidEtymologyHeaders(actual: table.headers)
            }
        }

        return try measurePhase("sidecar validation") {
            let validLevels = Set(definitions.map(\.level))
            var keys = Set<String>()
            return try table.rows.map { row in
                guard row.fields.count == Self.etymologyHeaders.count else {
                    throw BuiltInWordBookError.invalidEtymologyRow(line: row.lineNumber, reason: "列数必须为 7")
                }
                let fields = row.fields.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                guard validLevels.contains(fields[0]) else {
                    throw BuiltInWordBookError.invalidEtymologyRow(line: row.lineNumber, reason: "未知词书 \(fields[0])")
                }
                guard fields[1...4].allSatisfy({ !$0.isEmpty }) else {
                    throw BuiltInWordBookError.invalidEtymologyRow(line: row.lineNumber, reason: "匹配键和来源字段不能为空")
                }
                guard let isWasei = parseBoolean(fields[5]), let isPartial = parseBoolean(fields[6]) else {
                    throw BuiltInWordBookError.invalidEtymologyRow(line: row.lineNumber, reason: "布尔字段必须为 true 或 false")
                }
                let key = fields[0...2].joined(separator: "\u{1F}")
                guard keys.insert(key).inserted else {
                    throw BuiltInWordBookError.invalidEtymologyRow(line: row.lineNumber, reason: "wordBook + expression + reading 重复")
                }
                return BuiltInLoanwordEtymology(
                    wordBook: fields[0],
                    expression: fields[1],
                    reading: fields[2],
                    sourceTerm: fields[3],
                    sourceLanguageCode: fields[4],
                    isWasei: isWasei,
                    isPartial: isPartial
                )
            }
        }
    }

    private func measurePhase<T>(
        _ name: String,
        operation: () throws -> T
    ) rethrows -> T {
        let start = ContinuousClock.now
        defer {
            let elapsed = start.duration(to: .now)
            phaseRecorder?(name, elapsed)
            PerformanceTrace.record("Built-in seed \(name)", elapsed: elapsed)
        }
        return try operation()
    }

    private func parseBoolean(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }

    private func applyEtymologies(
        _ etymologies: [BuiltInLoanwordEtymology],
        to books: [WordBook],
        now: Date
    ) {
        let displayNameByLevel = Dictionary(uniqueKeysWithValues: definitions.map { ($0.level, $0.displayName) })
        let booksByName = Dictionary(uniqueKeysWithValues: books.filter(\.isBuiltIn).map { ($0.name, $0) })

        let expectedByBookAndWord = Dictionary(
            uniqueKeysWithValues: etymologies.map {
                ([ $0.wordBook, $0.expression, $0.reading ].joined(separator: "\u{1F}"), $0)
            }
        )

        // The sidecar is the complete expected state for built-in metadata.
        // Clear stale values only inside managed built-in books; user books are
        // never inspected or changed here.
        for definition in definitions {
            guard let book = booksByName[definition.displayName] else { continue }
            for word in book.words {
                let key = [definition.level, word.japanese, word.kana].joined(separator: "\u{1F}")
                guard expectedByBookAndWord[key] == nil else { continue }
                if word.loanwordSourceTerm != nil || word.loanwordSourceLanguageCode != nil
                    || word.loanwordIsWasei || word.loanwordIsPartial {
                    word.loanwordSourceTerm = nil
                    word.loanwordSourceLanguageCode = nil
                    word.loanwordIsWasei = false
                    word.loanwordIsPartial = false
                    word.updatedAt = now
                }
            }
        }

        for item in etymologies {
            guard let displayName = displayNameByLevel[item.wordBook], let book = booksByName[displayName] else { continue }
            let matches = book.words.filter { $0.japanese == item.expression && $0.kana == item.reading }
            guard matches.count == 1, let word = matches.first else { continue }
            word.loanwordSourceTerm = item.sourceTerm
            word.loanwordSourceLanguageCode = item.sourceLanguageCode
            word.loanwordIsWasei = item.isWasei
            word.loanwordIsPartial = item.isPartial
            word.updatedAt = now
        }
    }

    private func builtInWordCounts(
        in context: ModelContext,
        books: [WordBook]
    ) throws -> [String: Int]? {
        var counts: [String: Int] = [:]

        for definition in definitions {
            guard let book = books.first(where: { $0.isBuiltIn && $0.name == definition.displayName }) else {
                return nil
            }

            let bookID = book.id
            let descriptor = FetchDescriptor<VocabularyWord>(predicate: #Predicate { word in
                word.wordBook?.id == bookID && !word.isArchived
            })
            let actualCount = try context.fetchCount(descriptor)
            if let expected = definition.expectedWordCount {
                guard actualCount == expected else { return nil }
            } else {
                guard actualCount > 0 else { return nil }
            }
            counts[definition.level] = actualCount
        }

        return counts
    }

    private func loadResults(
        wordCounts: [String: Int],
        importedCounts: [String: Int]
    ) -> [BuiltInWordBookLoadResult] {
        definitions.map { definition in
            BuiltInWordBookLoadResult(
                level: definition.level,
                displayName: definition.displayName,
                wordCount: wordCounts[definition.level, default: 0],
                importedWordCount: importedCounts[definition.level, default: 0]
            )
        }
    }

    private func makeWord(from record: CSVRecord, wordBook: WordBook, now: Date) -> VocabularyWord {
        let fields = record.fields.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let word = VocabularyWord(
            japanese: fields[0],
            kana: fields[1],
            chineseMeaning: fields[2],
            partOfSpeech: partOfSpeechTokenizer.normalized(fields[3]),
            jlptLevel: fields[6],
            exampleJapanese: fields[4],
            exampleChinese: fields[5],
            tags: parseTags(fields[7]),
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

    private func applyConjugationAuditCorrections(
        to wordBook: WordBook,
        level: String,
        now: Date
    ) {
        var wordsByKey: [VocabularyWordImportKey: VocabularyWord] = [:]
        for word in wordBook.words {
            let key = VocabularyWordImportKey(expression: word.japanese, reading: word.kana)
            if wordsByKey[key] == nil {
                wordsByKey[key] = word
            }
        }

        for correction in Self.conjugationAuditCorrections where correction.level == level {
            let key = VocabularyWordImportKey(
                expression: correction.expression,
                reading: correction.reading
            )
            guard let word = wordsByKey[key],
                  word.partOfSpeech == correction.oldPartOfSpeech else {
                continue
            }
            word.partOfSpeech = correction.newPartOfSpeech
            word.updatedAt = now
        }
    }

    private func refresh(
        _ wordBook: WordBook,
        from rows: [CSVRecord],
        in context: ModelContext,
        now: Date,
        repairsReadingNormalizationDuplicates: Bool
    ) -> Int {
        var existingWords: [VocabularyWordImportKey: VocabularyWord] = [:]
        var equivalentWords: [VocabularyWordImportKey: VocabularyWord] = [:]
        for word in wordBook.words {
            let key = VocabularyWordImportKey(expression: word.japanese, reading: word.kana)
            if existingWords[key] == nil {
                existingWords[key] = word
            }

            let equivalentKey = equivalentVocabularyKey(expression: word.japanese, reading: word.kana)
            if equivalentWords[equivalentKey] == nil {
                equivalentWords[equivalentKey] = word
            }
        }

        let sourceKeys = Set(rows.map { VocabularyWordImportKey(expression: $0.fields[0], reading: $0.fields[1]) })
        let sourceEquivalentKeys = Set(rows.map { equivalentVocabularyKey(expression: $0.fields[0], reading: $0.fields[1]) })
        var importedCount = 0
        for row in rows {
            let key = VocabularyWordImportKey(expression: row.fields[0], reading: row.fields[1])
            if let existingWord = existingWords[key] {
                apply(row, to: existingWord, now: now)
                existingWord.isArchived = false
            } else if let equivalentWord = equivalentWords[equivalentVocabularyKey(expression: row.fields[0], reading: row.fields[1])] {
                apply(row, to: equivalentWord, now: now)
                equivalentWord.isArchived = false
            } else {
                let word = makeWord(from: row, wordBook: wordBook, now: now)
                context.insert(word)
                importedCount += 1
            }
        }

        if repairsReadingNormalizationDuplicates {
            removeSafeEquivalentDuplicates(in: wordBook, sourceRows: rows, context: context)
        }

        for word in wordBook.words {
            let exactKey = VocabularyWordImportKey(expression: word.japanese, reading: word.kana)
            let equivalentKey = equivalentVocabularyKey(expression: word.japanese, reading: word.kana)
            guard !sourceKeys.contains(exactKey), !sourceEquivalentKeys.contains(equivalentKey) else { continue }
            if isSafeToDeleteStaleBuiltInWord(word) {
                context.delete(word)
            } else {
                word.isArchived = true
                word.updatedAt = now
            }
        }

        return importedCount
    }

    private func isSafeToDeleteStaleBuiltInWord(_ word: VocabularyWord) -> Bool {
        guard !word.isFavorite, word.reviewLogs.isEmpty, let progress = word.progress else { return false }
        return progress.state == .new
            && progress.intervalDays == 0
            && progress.reviewCount == 0
            && progress.lapseCount == 0
            && progress.lastReviewedAt == nil
    }

    private func removeSafeEquivalentDuplicates(
        in wordBook: WordBook,
        sourceRows: [CSVRecord],
        context: ModelContext
    ) {
        let sourceReadings = Dictionary(
            uniqueKeysWithValues: sourceRows.map { row in
                (equivalentVocabularyKey(expression: row.fields[0], reading: row.fields[1]), row.fields[1])
            }
        )
        let groups = Dictionary(grouping: wordBook.words, by: { word in
            equivalentVocabularyKey(expression: word.japanese, reading: word.kana)
        })

        for (key, words) in groups where words.count > 1 {
            let preferredReading = sourceReadings[key]
            let keeper = words.first(where: { $0.kana == preferredReading })
                ?? words.first(where: { !isSafeToDeleteEquivalentDuplicate($0) })
                ?? words.min(by: { $0.createdAt < $1.createdAt })

            guard let keeper else {
                continue
            }

            for word in words where word.id != keeper.id {
                guard isSafeToDeleteEquivalentDuplicate(word) else {
                    continue
                }
                context.delete(word)
            }
        }
    }

    private func isSafeToDeleteEquivalentDuplicate(_ word: VocabularyWord) -> Bool {
        guard word.reviewLogs.isEmpty,
              let progress = word.progress else {
            return false
        }

        return progress.state == .new
            && progress.intervalDays == 0
            && progress.reviewCount == 0
            && progress.lapseCount == 0
            && progress.lastReviewedAt == nil
    }

    private func equivalentVocabularyKey(expression: String, reading: String) -> VocabularyWordImportKey {
        VocabularyWordImportKey(
            expression: normalizedHeadwordMarker(expression),
            reading: hiraganaReading(normalizedHeadwordMarker(reading))
        )
    }

    private func normalizedHeadwordMarker(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("〜") else {
            return trimmed
        }

        return String(trimmed.dropFirst())
    }

    private func hiraganaReading(_ reading: String) -> String {
        let scalars = reading.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.map { scalar -> UnicodeScalar in
            guard scalar.value >= 0x30A1, scalar.value <= 0x30F6,
                  let hiraganaScalar = UnicodeScalar(scalar.value - 0x60) else {
                return scalar
            }
            return hiraganaScalar
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private func apply(_ record: CSVRecord, to word: VocabularyWord, now: Date) {
        let fields = record.fields.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        word.japanese = fields[0]
        word.kana = fields[1]
        word.chineseMeaning = fields[2]
        word.partOfSpeech = partOfSpeechTokenizer.normalized(fields[3])
        word.jlptLevel = fields[6]
        word.exampleJapanese = fields[4]
        word.exampleChinese = fields[5]
        word.tags = parseTags(fields[7])
        word.updatedAt = now
    }

    private func parseTags(_ rawValue: String) -> [String] {
        var seen = Set<String>()
        return rawValue.split(separator: ";", omittingEmptySubsequences: true).compactMap { tag in
            let value = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, seen.insert(value).inserted else {
                return nil
            }
            return value
        }
    }

    private func containsProhibitedContent(_ value: String) -> Bool {
        value.range(of: #"<[^>]+>"#, options: .regularExpression) != nil
            || value.range(of: #"\[sound:[^\]]+\.mp3\]"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func resourceURL(for definition: BuiltInWordBookDefinition, in bundle: Bundle) -> URL? {
        let resourceName = definition.fileName.replacingOccurrences(of: ".csv", with: "")
        return bundle.url(forResource: resourceName, withExtension: "csv")
            ?? bundle.url(forResource: resourceName, withExtension: "csv", subdirectory: "Resources")
    }
}
