//
//  BuiltInWordBookServiceTests.swift
//  KotobaTests
//

import Foundation
import SwiftData
import XCTest
@testable import Kotoba

@MainActor
final class BuiltInWordBookServiceTests: XCTestCase {
    func testLoadsFiveIndependentJLPTWordBooksInDisplayOrder() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let userDefaults = try makeSeedDefaults()
        let definitions = BuiltInWordBookDefinition.all.map {
            BuiltInWordBookDefinition(
                level: $0.level,
                displayName: $0.displayName,
                fileName: $0.fileName,
                expectedWordCount: 1
            )
        }
        let service = BuiltInWordBookService(definitions: definitions, dataProvider: { definition in
            Data(
                """
                expression,reading,meaningChinese,partOfSpeech,exampleJapanese,exampleChinese,jlptLevel,tags
                学生,がくせい,学生,名词,"彼は\"\"学生\"\"です。",他是学生。,\(definition.level),学校;\(definition.level)
                """.utf8
            )
        }, userDefaults: userDefaults)

        let results = try service.loadIfNeeded(in: context, now: Date(timeIntervalSinceReferenceDate: 1_000))
        _ = try service.loadIfNeeded(in: context, now: Date(timeIntervalSinceReferenceDate: 2_000))
        let books = try WordBookService().fetchWordBooks(in: context)
        let words = try context.fetch(FetchDescriptor<VocabularyWord>())

        XCTAssertEqual(results.map(\.level), ["N5", "N4", "N3", "N2", "N1"])
        XCTAssertEqual(results.map(\.wordCount), [1, 1, 1, 1, 1])
        XCTAssertEqual(results.map(\.importedWordCount), [1, 1, 1, 1, 1])
        XCTAssertEqual(books.map(\.name), ["JLPT N5", "JLPT N4", "JLPT N3", "JLPT N2", "JLPT N1"])
        XCTAssertTrue(books.allSatisfy(\.isBuiltIn))
        XCTAssertEqual(words.count, 5)
        XCTAssertTrue(words.allSatisfy { $0.japanese == "学生" && $0.progress?.state == .new })
        XCTAssertEqual(userDefaults.integer(forKey: AppSettings.builtInWordBookSeedVersionKey), BuiltInWordBookService.builtInVocabularyVersion)
    }

    func testRejectsAHeaderThatDoesNotExactlyMatchTheBuiltInSchema() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let definition = BuiltInWordBookDefinition(level: "N5", displayName: "JLPT N5", fileName: "test.csv")
        let service = BuiltInWordBookService(definitions: [definition], dataProvider: { _ in
            Data("expression,reading,meaningChinese\n学生,がくせい,学生\n".utf8)
        }, userDefaults: try makeSeedDefaults())

        XCTAssertThrowsError(try service.loadIfNeeded(in: context)) { error in
            guard case BuiltInWordBookError.invalidHeaders(let fileName, _) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(fileName, "test.csv")
        }
    }

    func testRejectsMismatchedJLPTLevelAndProhibitedContent() throws {
        let definition = BuiltInWordBookDefinition(level: "N5", displayName: "JLPT N5", fileName: "test.csv")

        let mismatchedContainer = try makeInMemoryTestContainer()
        let mismatchedService = BuiltInWordBookService(definitions: [definition], dataProvider: { _ in
            Data("expression,reading,meaningChinese,partOfSpeech,exampleJapanese,exampleChinese,jlptLevel,tags\n学生,がくせい,学生,名词,,,N4,学校\n".utf8)
        }, userDefaults: try makeSeedDefaults())
        XCTAssertThrowsError(try mismatchedService.loadIfNeeded(in: mismatchedContainer.mainContext)) { error in
            guard case BuiltInWordBookError.mismatchedJLPTLevel(_, _, let actual, let expected) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(actual, "N4")
            XCTAssertEqual(expected, "N5")
        }

        let contentContainer = try makeInMemoryTestContainer()
        let contentService = BuiltInWordBookService(definitions: [definition], dataProvider: { _ in
            Data("expression,reading,meaningChinese,partOfSpeech,exampleJapanese,exampleChinese,jlptLevel,tags\n学生,がくせい,<b>学生</b>,名词,,,N5,学校\n".utf8)
        }, userDefaults: try makeSeedDefaults())
        XCTAssertThrowsError(try contentService.loadIfNeeded(in: contentContainer.mainContext)) { error in
            XCTAssertEqual(error as? BuiltInWordBookError, .prohibitedContent(fileName: "test.csv", line: 2))
        }
    }

    func testRejectsMissingReadingAndNonStandardSeparators() throws {
        let definition = BuiltInWordBookDefinition(level: "N5", displayName: "JLPT N5", fileName: "test.csv")

        let missingReadingContainer = try makeInMemoryTestContainer()
        let missingReadingService = BuiltInWordBookService(definitions: [definition], dataProvider: { _ in
            Data("expression,reading,meaningChinese,partOfSpeech,exampleJapanese,exampleChinese,jlptLevel,tags\n学生,,学生,名词,,,N5,学校\n".utf8)
        }, userDefaults: try makeSeedDefaults())
        XCTAssertThrowsError(try missingReadingService.loadIfNeeded(in: missingReadingContainer.mainContext)) { error in
            XCTAssertEqual(
                error as? BuiltInWordBookError,
                .missingRequiredValue(fileName: "test.csv", line: 2, field: "reading")
            )
        }

        let separatorContainer = try makeInMemoryTestContainer()
        let separatorService = BuiltInWordBookService(definitions: [definition], dataProvider: { _ in
            Data("expression,reading,meaningChinese,partOfSpeech,exampleJapanese,exampleChinese,jlptLevel,tags\n学生,がくせい,学生,名词；な形容词,,,N5,学校；基础\n".utf8)
        }, userDefaults: try makeSeedDefaults())
        XCTAssertThrowsError(try separatorService.loadIfNeeded(in: separatorContainer.mainContext)) { error in
            XCTAssertEqual(error as? BuiltInWordBookError, .invalidPartOfSpeech(fileName: "test.csv", line: 2))
        }
    }

    func testRefreshesAnOlderBuiltInVersionWithoutDuplicatingMatchedWordsOrProgress() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let definition = BuiltInWordBookDefinition(level: "N5", displayName: "JLPT N5", fileName: "test.csv")
        let userDefaults = try makeSeedDefaults()
        userDefaults.set(0, forKey: AppSettings.builtInWordBookSeedVersionKey)
        let book = WordBook(name: definition.displayName, isBuiltIn: true)
        let existingWord = VocabularyWord(
            japanese: "学生",
            kana: "がくせい",
            chineseMeaning: "旧释义",
            partOfSpeech: "名词",
            jlptLevel: "N5",
            wordBook: book
        )
        existingWord.progress = LearningProgress(state: .review, dueAt: Date(), word: existingWord)
        let retainedWord = VocabularyWord(
            japanese: "保留",
            kana: "ほりゅう",
            chineseMeaning: "不在新版资源中的旧词",
            partOfSpeech: "名词",
            jlptLevel: "N5",
            wordBook: book
        )
        retainedWord.progress = LearningProgress(state: .review, dueAt: Date(), word: retainedWord)
        context.insert(book)
        context.insert(existingWord)
        context.insert(retainedWord)
        try context.save()

        let service = BuiltInWordBookService(definitions: [definition], dataProvider: { _ in
            Data("expression,reading,meaningChinese,partOfSpeech,exampleJapanese,exampleChinese,jlptLevel,tags\n学生,がくせい,学生（新版）,名词,,,N5,学校\n".utf8)
        }, userDefaults: userDefaults)
        let result = try service.loadIfNeeded(in: context)
        let words = try context.fetch(FetchDescriptor<VocabularyWord>())

        XCTAssertEqual(result.first?.importedWordCount, 0)
        XCTAssertEqual(words.count, 2)
        XCTAssertEqual(words.first(where: { $0.japanese == "学生" })?.chineseMeaning, "学生（新版）")
        XCTAssertEqual(words.first(where: { $0.japanese == "学生" })?.progress?.state, .review)
        XCTAssertEqual(words.first(where: { $0.japanese == "保留" })?.progress?.state, .review)
        XCTAssertEqual(userDefaults.integer(forKey: AppSettings.builtInWordBookSeedVersionKey), BuiltInWordBookService.builtInVocabularyVersion)
    }

    func testSidecarUpgradeAddsEtymologyWithoutReplacingLearningData() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let definition = BuiltInWordBookDefinition(level: "N5", displayName: "JLPT N5", fileName: "test.csv")
        let defaults = try makeSeedDefaults()
        defaults.set(5, forKey: AppSettings.builtInWordBookSeedVersionKey)
        let dueAt = Date(timeIntervalSinceReferenceDate: 90_000)
        let book = WordBook(name: definition.displayName, isBuiltIn: true)
        let word = VocabularyWord(
            japanese: "コンピューター", kana: "コンピューター", chineseMeaning: "电脑", jlptLevel: "N5",
            isFavorite: true, wordBook: book
        )
        let progress = LearningProgress(state: .review, dueAt: dueAt, intervalDays: 30, reviewCount: 8, word: word)
        let log = ReviewLog(
            rating: .good, previousState: .review, nextState: .review,
            previousIntervalDays: 15, nextIntervalDays: 30, scheduledDueAt: dueAt, word: word
        )
        word.progress = progress
        word.reviewLogs.append(log)
        context.insert(book)
        context.insert(word)
        context.insert(progress)
        context.insert(log)
        try context.save()
        let originalID = word.id
        let originalLogID = log.id

        let service = BuiltInWordBookService(
            definitions: [definition],
            dataProvider: { _ in
                Data("expression,reading,meaningChinese,partOfSpeech,exampleJapanese,exampleChinese,jlptLevel,tags\nコンピューター,コンピューター,电脑,名词,,,N5,外来语\n".utf8)
            },
            etymologyDataProvider: {
                Data("wordBook,expression,reading,sourceTerm,sourceLanguage,isWasei,isPartial\nN5,コンピューター,コンピューター,computer,eng,false,false\n".utf8)
            },
            userDefaults: defaults
        )
        _ = try service.loadIfNeeded(in: context)

        let upgraded = try XCTUnwrap(context.fetch(FetchDescriptor<VocabularyWord>()).first)
        XCTAssertEqual(upgraded.id, originalID)
        XCTAssertTrue(upgraded.isFavorite)
        XCTAssertEqual(upgraded.progress?.dueAt, dueAt)
        XCTAssertEqual(upgraded.progress?.reviewCount, 8)
        XCTAssertEqual(upgraded.reviewLogs.first?.id, originalLogID)
        XCTAssertEqual(upgraded.loanwordSourceTerm, "computer")
        XCTAssertEqual(upgraded.loanwordSourceLanguageCode, "eng")
        XCTAssertFalse(upgraded.loanwordIsWasei)
        XCTAssertFalse(upgraded.loanwordIsPartial)
    }

    func testBundledResourcesMatchTheCurrentImporterSchema() throws {
        let parser = CSVParser()

        for definition in BuiltInWordBookDefinition.all {
            let url = builtInResourceURL(for: definition)
            let text = try String(contentsOf: url, encoding: .utf8)
            let table = try parser.parse(text)

            XCTAssertEqual(table.headers, BuiltInWordBookService.requiredHeaders, definition.fileName)
            XCTAssertFalse(table.rows.isEmpty, definition.fileName)

            var keys = Set<String>()
            for record in table.rows {
                XCTAssertEqual(record.fields.count, 8, "\(definition.fileName):\(record.lineNumber)")
                XCTAssertFalse(record.fields[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                XCTAssertFalse(record.fields[1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                XCTAssertFalse(record.fields[0].hasPrefix("〜"), "\(definition.fileName):\(record.lineNumber)")
                XCTAssertFalse(record.fields[1].hasPrefix("〜"), "\(definition.fileName):\(record.lineNumber)")
                XCTAssertFalse(record.fields[2].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                XCTAssertEqual(record.fields[6], definition.level, "\(definition.fileName):\(record.lineNumber)")
                XCTAssertFalse(record.fields[3].contains("；"))
                XCTAssertFalse(record.fields[3].contains(";"))
                XCTAssertFalse(record.fields[7].contains("；"))

                let key = "\(record.fields[0])\u{1F}\(record.fields[1])"
                XCTAssertTrue(keys.insert(key).inserted, "\(definition.fileName):\(record.lineNumber)")
            }
        }
    }

    func testBundledEtymologySidecarHasStrictIndependentSchemaAndUniqueKeys() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Kotoba/Resources/builtin_loanword_etymology.csv")
        let table = try CSVParser().parse(String(contentsOf: url, encoding: .utf8))
        XCTAssertEqual(table.headers, BuiltInWordBookService.etymologyHeaders)
        XCTAssertEqual(table.rows.count, 46)
        let parser = CSVParser()
        var builtInKeys = Set<String>()
        for definition in BuiltInWordBookDefinition.all {
            let wordTable = try parser.parse(
                String(contentsOf: builtInResourceURL(for: definition), encoding: .utf8)
            )
            for row in wordTable.rows {
                builtInKeys.insert(
                    [definition.level, row.fields[0], row.fields[1]].joined(separator: "\u{1F}")
                )
            }
        }
        var keys = Set<String>()
        for row in table.rows {
            XCTAssertEqual(row.fields.count, 7)
            let key = row.fields[0...2].joined(separator: "\u{1F}")
            XCTAssertTrue(keys.insert(key).inserted)
            XCTAssertTrue(builtInKeys.contains(key), "Sidecar row does not match a built-in word: \(key)")
            XCTAssertFalse(row.fields[3].isEmpty)
            XCTAssertFalse(row.fields[4].isEmpty)
            XCTAssertNotNil(Bool(row.fields[5]))
            XCTAssertNotNil(Bool(row.fields[6]))
        }
    }

    func testBundledSampleCSVDoesNotUseLeadingWaveHeadwordMarker() throws {
        let parser = CSVParser()
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Kotoba/Resources/sample_kotoba_vocabulary.csv")
        let table = try parser.parse(String(contentsOf: url, encoding: .utf8))

        XCTAssertEqual(table.headers, BuiltInWordBookService.requiredHeaders)
        for record in table.rows {
            XCTAssertFalse(record.fields[0].hasPrefix("〜"), "sample_kotoba_vocabulary.csv:\(record.lineNumber)")
            XCTAssertFalse(record.fields[1].hasPrefix("〜"), "sample_kotoba_vocabulary.csv:\(record.lineNumber)")
        }
    }

    func testRefreshRemovesLegacyLeadingWaveMarkerWithoutResettingProgress() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let definition = BuiltInWordBookDefinition(level: "N5", displayName: "JLPT N5", fileName: "test.csv")
        let userDefaults = try makeSeedDefaults()
        userDefaults.set(3, forKey: AppSettings.builtInWordBookSeedVersionKey)
        let book = WordBook(name: definition.displayName, isBuiltIn: true)
        let existingWord = VocabularyWord(
            japanese: "〜さん",
            kana: "〜さん",
            chineseMeaning: "旧释义",
            partOfSpeech: "接尾词",
            jlptLevel: "N5",
            wordBook: book
        )
        existingWord.progress = LearningProgress(state: .review, dueAt: Date(), reviewCount: 4, word: existingWord)
        context.insert(book)
        context.insert(existingWord)
        try context.save()

        let service = BuiltInWordBookService(
            definitions: [definition],
            dataProvider: { _ in
                Data(
                    """
                    expression,reading,meaningChinese,partOfSpeech,exampleJapanese,exampleChinese,jlptLevel,tags
                    さん,さん,先生，女士,接尾词,佐藤さん,佐藤先生,N5,eggrolls;原词性:接尾
                    """.utf8
                )
            },
            userDefaults: userDefaults
        )

        _ = try service.loadIfNeeded(in: context)
        let words = try context.fetch(FetchDescriptor<VocabularyWord>())

        XCTAssertEqual(words.count, 1)
        XCTAssertEqual(words.first?.id, existingWord.id)
        XCTAssertEqual(words.first?.japanese, "さん")
        XCTAssertEqual(words.first?.kana, "さん")
        XCTAssertEqual(words.first?.progress?.state, .review)
        XCTAssertEqual(words.first?.progress?.reviewCount, 4)
    }

    func testBundledResourcesSeedFiveBooksIdempotently() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let userDefaults = try makeSeedDefaults()
        let service = BuiltInWordBookService(dataProvider: { definition in
            try Data(contentsOf: self.builtInResourceURL(for: definition))
        }, userDefaults: userDefaults)

        let firstLoad = try service.loadIfNeeded(in: context)
        let secondLoad = try service.loadIfNeeded(in: context)
        let books = try WordBookService().fetchWordBooks(in: context)
        let words = try context.fetch(FetchDescriptor<VocabularyWord>())

        XCTAssertEqual(firstLoad.map(\.wordCount), [802, 755, 1_817, 3_206, 4_029])
        XCTAssertEqual(firstLoad.map(\.importedWordCount), [802, 755, 1_817, 3_206, 4_029])
        XCTAssertEqual(secondLoad.map(\.importedWordCount), [0, 0, 0, 0, 0])
        XCTAssertEqual(books.filter(\.isBuiltIn).count, 5)
        XCTAssertEqual(words.count, 10_609)
    }

    func testCurrentCompleteSeedSkipsResourceReads() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let userDefaults = try makeSeedDefaults()
        let definition = BuiltInWordBookDefinition(
            level: "N5",
            displayName: "JLPT N5",
            fileName: "test.csv",
            expectedWordCount: 1
        )
        let book = WordBook(name: definition.displayName, isBuiltIn: true)
        let word = VocabularyWord(
            japanese: "学生",
            kana: "がくせい",
            chineseMeaning: "学生",
            jlptLevel: "N5",
            wordBook: book
        )
        word.progress = LearningProgress(state: .new, word: word)
        book.words = [word]
        context.insert(book)
        context.insert(word)
        try context.save()
        userDefaults.set(BuiltInWordBookService.builtInVocabularyVersion, forKey: AppSettings.builtInWordBookSeedVersionKey)

        var secondReadCount = 0
        let secondService = BuiltInWordBookService(
            definitions: [definition],
            dataProvider: { _ in
                secondReadCount += 1
                return Data()
            },
            userDefaults: userDefaults
        )
        let results = try secondService.loadIfNeeded(in: context)

        XCTAssertEqual(secondReadCount, 0)
        XCTAssertEqual(results.first?.wordCount, 1)
        XCTAssertEqual(results.first?.importedWordCount, 0)
    }

    func testCurrentSeedVersionRepairsPartiallyMissingBookInsteadOfFastPathing() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let defaults = try makeSeedDefaults()
        let definition = BuiltInWordBookDefinition(
            level: "N5",
            displayName: "JLPT N5",
            fileName: "test.csv",
            expectedWordCount: 2
        )
        let book = WordBook(name: definition.displayName, isBuiltIn: true)
        let retained = VocabularyWord(
            japanese: "学生", kana: "がくせい", chineseMeaning: "旧释义", jlptLevel: "N5", wordBook: book
        )
        retained.progress = LearningProgress(state: .review, intervalDays: 9, reviewCount: 4, word: retained)
        context.insert(book)
        context.insert(retained)
        try context.save()
        defaults.set(BuiltInWordBookService.builtInVocabularyVersion, forKey: AppSettings.builtInWordBookSeedVersionKey)

        var resourceReadCount = 0
        let service = BuiltInWordBookService(
            definitions: [definition],
            dataProvider: { _ in
                resourceReadCount += 1
                return Data(
                    "expression,reading,meaningChinese,partOfSpeech,exampleJapanese,exampleChinese,jlptLevel,tags\n学生,がくせい,新版,名词,,,N5,学校\n先生,せんせい,老师,名词,,,N5,学校\n".utf8
                )
            },
            userDefaults: defaults
        )
        let result = try service.loadIfNeeded(in: context)

        XCTAssertEqual(resourceReadCount, 1)
        XCTAssertEqual(result.first?.wordCount, 2)
        XCTAssertEqual(result.first?.importedWordCount, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<VocabularyWord>()), 2)
        XCTAssertEqual(retained.progress?.state, .review)
        XCTAssertEqual(retained.progress?.intervalDays, 9)
        XCTAssertEqual(retained.progress?.reviewCount, 4)
    }

    func testRefreshDeletesOnlySafeStaleWordsAndArchivesProtectedHistory() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let definition = BuiltInWordBookDefinition(level: "N5", displayName: "JLPT N5", fileName: "test.csv", expectedWordCount: 1)
        let book = WordBook(name: definition.displayName, isBuiltIn: true)
        let current = VocabularyWord(japanese: "学生", kana: "がくせい", chineseMeaning: "学生", jlptLevel: "N5", wordBook: book)
        current.progress = LearningProgress(state: .new, word: current)
        let safeStale = VocabularyWord(japanese: "旧词", kana: "きゅうご", chineseMeaning: "旧", jlptLevel: "N5", wordBook: book)
        safeStale.progress = LearningProgress(state: .new, word: safeStale)
        let protectedStale = VocabularyWord(
            japanese: "历史词", kana: "れきしご", chineseMeaning: "历史", jlptLevel: "N5", isFavorite: true, wordBook: book
        )
        protectedStale.progress = LearningProgress(state: .review, intervalDays: 5, reviewCount: 2, word: protectedStale)
        protectedStale.reviewLogs = [
            ReviewLog(
                rating: .again, previousState: .review, nextState: .relearning,
                previousIntervalDays: 5, nextIntervalDays: 0, scheduledDueAt: Date(), word: protectedStale
            )
        ]
        context.insert(book)
        context.insert(current)
        context.insert(safeStale)
        context.insert(protectedStale)
        try context.save()

        let service = BuiltInWordBookService(
            definitions: [definition],
            dataProvider: { _ in
                Data("expression,reading,meaningChinese,partOfSpeech,exampleJapanese,exampleChinese,jlptLevel,tags\n学生,がくせい,学生,名词,,,N5,学校\n".utf8)
            },
            userDefaults: try makeSeedDefaults()
        )
        _ = try service.loadIfNeeded(in: context)
        let words = try context.fetch(FetchDescriptor<VocabularyWord>())

        XCTAssertNil(words.first(where: { $0.id == safeStale.id }))
        XCTAssertTrue(try XCTUnwrap(words.first(where: { $0.id == protectedStale.id })).isArchived)
        XCTAssertEqual(protectedStale.reviewLogs.count, 1)
        XCTAssertEqual(protectedStale.progress?.state, .review)
    }

    func testSidecarRemovalClearsBuiltInMetadataButNotUserWord() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let defaults = try makeSeedDefaults()
        defaults.set(5, forKey: AppSettings.builtInWordBookSeedVersionKey)
        let definition = BuiltInWordBookDefinition(level: "N5", displayName: "JLPT N5", fileName: "test.csv", expectedWordCount: 1)
        let builtInBook = WordBook(name: definition.displayName, isBuiltIn: true)
        let userBook = WordBook(name: "用户词书")
        let builtInWord = VocabularyWord(
            japanese: "コンピューター", kana: "コンピューター", chineseMeaning: "电脑", jlptLevel: "N5",
            loanwordSourceTerm: "computer", loanwordSourceLanguageCode: "eng", loanwordIsPartial: true, wordBook: builtInBook
        )
        builtInWord.progress = LearningProgress(state: .new, word: builtInWord)
        let userWord = VocabularyWord(
            japanese: "コンピューター", kana: "コンピューター", chineseMeaning: "电脑", jlptLevel: "N5",
            loanwordSourceTerm: "custom", loanwordSourceLanguageCode: "user", loanwordIsWasei: true, wordBook: userBook
        )
        userWord.progress = LearningProgress(state: .new, word: userWord)
        context.insert(builtInBook)
        context.insert(userBook)
        context.insert(builtInWord)
        context.insert(userWord)
        try context.save()

        let service = BuiltInWordBookService(
            definitions: [definition],
            dataProvider: { _ in
                Data("expression,reading,meaningChinese,partOfSpeech,exampleJapanese,exampleChinese,jlptLevel,tags\nコンピューター,コンピューター,电脑,名词,,,N5,外来语\n".utf8)
            },
            etymologyDataProvider: {
                Data("wordBook,expression,reading,sourceTerm,sourceLanguage,isWasei,isPartial\n".utf8)
            },
            userDefaults: defaults
        )
        _ = try service.loadIfNeeded(in: context)

        XCTAssertNil(builtInWord.loanwordSourceTerm)
        XCTAssertNil(builtInWord.loanwordSourceLanguageCode)
        XCTAssertFalse(builtInWord.loanwordIsWasei)
        XCTAssertFalse(builtInWord.loanwordIsPartial)
        XCTAssertEqual(userWord.loanwordSourceTerm, "custom")
        XCTAssertEqual(userWord.loanwordSourceLanguageCode, "user")
        XCTAssertTrue(userWord.loanwordIsWasei)
    }

    func testSeedingDoesNotModifyAUserWordBookOrItsProgress() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let userBook = WordBook(name: "JLPT N5")
        let userWord = VocabularyWord(
            japanese: "自定义",
            kana: "じていぎ",
            chineseMeaning: "用户自己的词条",
            jlptLevel: "N5",
            wordBook: userBook
        )
        userWord.progress = LearningProgress(state: .review, dueAt: Date(), word: userWord)
        context.insert(userBook)
        context.insert(userWord)
        try context.save()

        let definition = BuiltInWordBookDefinition(level: "N5", displayName: "JLPT N5", fileName: "test.csv")
        let service = BuiltInWordBookService(definitions: [definition], dataProvider: { _ in
            Data("expression,reading,meaningChinese,partOfSpeech,exampleJapanese,exampleChinese,jlptLevel,tags\n学生,がくせい,学生,名词,,,N5,学校\n".utf8)
        }, userDefaults: try makeSeedDefaults())
        _ = try service.loadIfNeeded(in: context)

        let books = try WordBookService().fetchWordBooks(in: context)
        let words = try context.fetch(FetchDescriptor<VocabularyWord>())

        XCTAssertEqual(books.count, 2)
        XCTAssertEqual(words.first(where: { $0.id == userWord.id })?.wordBook?.id, userBook.id)
        XCTAssertEqual(words.first(where: { $0.id == userWord.id })?.progress?.state, .review)
        XCTAssertEqual(books.first(where: { $0.isBuiltIn })?.name, "JLPT N5")
    }

    func testRepairsAStaleSeedFlagWhenTheBuiltInBookIsMissingOrEmpty() throws {
        let definition = BuiltInWordBookDefinition(level: "N5", displayName: "JLPT N5", fileName: "test.csv")
        let userDefaults = try makeSeedDefaults()
        userDefaults.set(BuiltInWordBookService.builtInVocabularyVersion, forKey: AppSettings.builtInWordBookSeedVersionKey)
        let service = BuiltInWordBookService(definitions: [definition], dataProvider: { _ in
            Data("expression,reading,meaningChinese,partOfSpeech,exampleJapanese,exampleChinese,jlptLevel,tags\n学生,がくせい,学生,名词,,,N5,学校\n".utf8)
        }, userDefaults: userDefaults)

        let missingContainer = try makeInMemoryTestContainer()
        _ = try service.loadIfNeeded(in: missingContainer.mainContext)
        XCTAssertEqual(try missingContainer.mainContext.fetch(FetchDescriptor<WordBook>()).count, 1)

        let emptyContainer = try makeInMemoryTestContainer()
        let emptyBook = WordBook(name: definition.displayName, isBuiltIn: true)
        emptyContainer.mainContext.insert(emptyBook)
        try emptyContainer.mainContext.save()
        _ = try service.loadIfNeeded(in: emptyContainer.mainContext)
        XCTAssertEqual(try emptyContainer.mainContext.fetch(FetchDescriptor<VocabularyWord>()).count, 1)
    }

    func testEquivalentKatakanaReadingUpdatesExistingWordWithoutAddingADuplicate() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let definition = BuiltInWordBookDefinition(level: "N5", displayName: "JLPT N5", fileName: "test.csv")
        let book = WordBook(name: definition.displayName, isBuiltIn: true)
        let existingWord = VocabularyWord(
            japanese: "テスト",
            kana: "テスト",
            chineseMeaning: "旧释义",
            jlptLevel: "N5",
            wordBook: book
        )
        existingWord.progress = LearningProgress(state: .review, dueAt: Date(), word: existingWord)
        context.insert(book)
        context.insert(existingWord)
        try context.save()

        let userDefaults = try makeSeedDefaults()
        let service = BuiltInWordBookService(definitions: [definition], dataProvider: { _ in
            Data("expression,reading,meaningChinese,partOfSpeech,exampleJapanese,exampleChinese,jlptLevel,tags\nテスト,てすと,测试,名词,,,N5,外来语\n".utf8)
        }, userDefaults: userDefaults)
        _ = try service.loadIfNeeded(in: context)

        let words = try context.fetch(FetchDescriptor<VocabularyWord>())
        XCTAssertEqual(words.count, 1)
        XCTAssertEqual(words.first?.kana, "てすと")
        XCTAssertEqual(words.first?.chineseMeaning, "测试")
        XCTAssertEqual(words.first?.progress?.state, .review)
    }

    func testSafeEquivalentDuplicateIsRemovedDuringBuiltInRefresh() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let definition = BuiltInWordBookDefinition(level: "N5", displayName: "JLPT N5", fileName: "test.csv")
        let book = WordBook(name: definition.displayName, isBuiltIn: true)
        let originalWord = VocabularyWord(
            japanese: "テスト",
            kana: "テスト",
            chineseMeaning: "测试",
            jlptLevel: "N5",
            createdAt: Date(timeIntervalSinceReferenceDate: 1),
            wordBook: book
        )
        originalWord.progress = LearningProgress(state: .new, word: originalWord)
        let generatedDuplicate = VocabularyWord(
            japanese: "テスト",
            kana: "てすと",
            chineseMeaning: "测试",
            jlptLevel: "N5",
            createdAt: Date(timeIntervalSinceReferenceDate: 2),
            wordBook: book
        )
        generatedDuplicate.progress = LearningProgress(state: .new, word: generatedDuplicate)
        context.insert(book)
        context.insert(originalWord)
        context.insert(generatedDuplicate)
        try context.save()

        let userDefaults = try makeSeedDefaults()
        userDefaults.set(2, forKey: AppSettings.builtInWordBookSeedVersionKey)
        let service = BuiltInWordBookService(
            definitions: [definition],
            dataProvider: { _ in
                Data("expression,reading,meaningChinese,partOfSpeech,exampleJapanese,exampleChinese,jlptLevel,tags\nテスト,テスト,测试,名词,,,N5,外来语\n".utf8)
            },
            userDefaults: userDefaults
        )
        _ = try service.loadIfNeeded(in: context)

        let words = try context.fetch(FetchDescriptor<VocabularyWord>())
        XCTAssertEqual(words.count, 1)
        XCTAssertEqual(words.first?.id, originalWord.id)
    }

    func testEquivalentDuplicateWithReviewHistoryIsPreserved() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let definition = BuiltInWordBookDefinition(level: "N5", displayName: "JLPT N5", fileName: "test.csv")
        let book = WordBook(name: definition.displayName, isBuiltIn: true)
        let originalWord = VocabularyWord(japanese: "テスト", kana: "テスト", chineseMeaning: "测试", jlptLevel: "N5", wordBook: book)
        originalWord.progress = LearningProgress(state: .new, word: originalWord)
        let protectedDuplicate = VocabularyWord(japanese: "テスト", kana: "てすと", chineseMeaning: "测试", jlptLevel: "N5", wordBook: book)
        protectedDuplicate.progress = LearningProgress(state: .review, dueAt: Date(), word: protectedDuplicate)
        protectedDuplicate.reviewLogs = [
            ReviewLog(
                rating: .good,
                previousState: .new,
                nextState: .review,
                previousIntervalDays: 0,
                nextIntervalDays: 2,
                scheduledDueAt: Date(),
                word: protectedDuplicate
            )
        ]
        context.insert(book)
        context.insert(originalWord)
        context.insert(protectedDuplicate)
        try context.save()

        let userDefaults = try makeSeedDefaults()
        userDefaults.set(2, forKey: AppSettings.builtInWordBookSeedVersionKey)
        let service = BuiltInWordBookService(
            definitions: [definition],
            dataProvider: { _ in
                Data("expression,reading,meaningChinese,partOfSpeech,exampleJapanese,exampleChinese,jlptLevel,tags\nテスト,テスト,测试,名词,,,N5,外来语\n".utf8)
            },
            userDefaults: userDefaults
        )
        _ = try service.loadIfNeeded(in: context)

        let words = try context.fetch(FetchDescriptor<VocabularyWord>())
        XCTAssertEqual(words.count, 2)
        XCTAssertEqual(words.first(where: { $0.id == protectedDuplicate.id })?.reviewLogs.count, 1)
    }

    func testVersionFourConjugationPatchChangesOnlyConfirmedFieldAndPreservesProgress() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let definition = BuiltInWordBookDefinition(
            level: "N5",
            displayName: "JLPT N5",
            fileName: "test.csv",
            expectedWordCount: 1
        )
        let userDefaults = try makeSeedDefaults()
        userDefaults.set(4, forKey: AppSettings.builtInWordBookSeedVersionKey)
        let originalUpdatedAt = Date(timeIntervalSinceReferenceDate: 50)
        let dueAt = Date(timeIntervalSinceReferenceDate: 5_000)
        let book = WordBook(name: definition.displayName, isBuiltIn: true)
        let word = VocabularyWord(
            japanese: "来る",
            kana: "くる",
            chineseMeaning: "保留的旧释义",
            partOfSpeech: "サ变动词/补助动词",
            jlptLevel: "N5",
            exampleJapanese: "保留的旧例句。",
            exampleChinese: "保留的旧译文。",
            tags: ["保留标签"],
            updatedAt: originalUpdatedAt,
            isFavorite: true,
            wordBook: book
        )
        let progress = LearningProgress(
            state: .review,
            dueAt: dueAt,
            intervalDays: 17,
            reviewCount: 9,
            lapseCount: 2,
            word: word
        )
        let log = ReviewLog(
            rating: .good,
            previousState: .learning,
            nextState: .review,
            previousIntervalDays: 1,
            nextIntervalDays: 2,
            scheduledDueAt: dueAt,
            word: word
        )
        word.progress = progress
        word.reviewLogs = [log]
        context.insert(book)
        context.insert(word)
        try context.save()
        let wordID = word.id
        let progressID = progress.id
        let logID = log.id
        let patchDate = Date(timeIntervalSinceReferenceDate: 10_000)

        let service = BuiltInWordBookService(
            definitions: [definition],
            dataProvider: { _ in
                Data(
                    "expression,reading,meaningChinese,partOfSpeech,exampleJapanese,exampleChinese,jlptLevel,tags\n来る,くる,新释义,动词/自动词/カ变动词/补助动词,新例句。,新译文。,N5,新标签\n".utf8
                )
            },
            userDefaults: userDefaults
        )
        let results = try service.loadIfNeeded(in: context, now: patchDate)
        let patched = try XCTUnwrap(try context.fetch(FetchDescriptor<VocabularyWord>()).first)

        XCTAssertEqual(results.first?.importedWordCount, 0)
        XCTAssertEqual(patched.id, wordID)
        XCTAssertEqual(patched.partOfSpeech, "动词/自动词/カ变动词/补助动词")
        XCTAssertEqual(patched.updatedAt, patchDate)
        XCTAssertEqual(patched.chineseMeaning, "保留的旧释义")
        XCTAssertEqual(patched.exampleJapanese, "保留的旧例句。")
        XCTAssertEqual(patched.exampleChinese, "保留的旧译文。")
        XCTAssertEqual(patched.tags, ["保留标签"])
        XCTAssertTrue(patched.isFavorite)
        XCTAssertEqual(patched.progress?.id, progressID)
        XCTAssertEqual(patched.progress?.state, .review)
        XCTAssertEqual(patched.progress?.dueAt, dueAt)
        XCTAssertEqual(patched.progress?.intervalDays, 17)
        XCTAssertEqual(patched.progress?.reviewCount, 9)
        XCTAssertEqual(patched.progress?.lapseCount, 2)
        XCTAssertEqual(patched.reviewLogs.map(\.id), [logID])
        XCTAssertEqual(userDefaults.integer(forKey: AppSettings.builtInWordBookSeedVersionKey), BuiltInWordBookService.builtInVocabularyVersion)
    }

    private func builtInResourceURL(for definition: BuiltInWordBookDefinition) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Kotoba/Resources")
            .appendingPathComponent(definition.fileName)
    }

    private func makeSeedDefaults() throws -> UserDefaults {
        let suiteName = "BuiltInWordBookServiceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
