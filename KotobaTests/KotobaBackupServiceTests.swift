//
//  KotobaBackupServiceTests.swift
//  KotobaTests
//

import SwiftData
import XCTest
@testable import Kotoba

@MainActor
final class KotobaBackupServiceTests: XCTestCase {
    func testV3BackupExportsAndImportsCoreUserDataAndEtymology() throws {
        let sourceContainer = try makeInMemoryTestContainer()
        let ids = try seedBackupFixture(in: sourceContainer.mainContext)
        let service = KotobaBackupService()

        let data = try service.exportBackup(
            in: sourceContainer.mainContext,
            exportedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        let decoded = try service.decodeBackup(from: data)

        XCTAssertEqual(decoded.schemaVersion, 3)
        XCTAssertEqual(decoded.wordBooks.count, 1)
        XCTAssertEqual(decoded.vocabularyWords.count, 1)
        XCTAssertEqual(decoded.learningProgress.count, 1)
        XCTAssertEqual(decoded.reviewLogs.count, 1)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("reviewLevel"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("conjugationRecords"))

        let targetContainer = try makeInMemoryTestContainer()
        let result = try service.importBackup(from: data, strategy: .merge, in: targetContainer.mainContext)

        XCTAssertEqual(result.insertedWordBookCount, 1)
        XCTAssertEqual(result.insertedWordCount, 1)
        XCTAssertEqual(result.insertedProgressCount, 1)
        XCTAssertEqual(result.insertedReviewLogCount, 1)

        let importedWord = try XCTUnwrap(
            targetContainer.mainContext.fetch(FetchDescriptor<VocabularyWord>()).first
        )
        XCTAssertEqual(importedWord.id, ids.wordID)
        XCTAssertEqual(importedWord.wordBook?.id, ids.wordBookID)
        XCTAssertEqual(importedWord.progress?.state, .review)
        XCTAssertEqual(importedWord.progress?.intervalDays, 4)
        XCTAssertEqual(importedWord.progress?.dueAt, ids.dueAt)
        XCTAssertTrue(importedWord.isFavorite)
        XCTAssertEqual(importedWord.loanwordSourceTerm, "computer")
        XCTAssertEqual(importedWord.loanwordSourceLanguageCode, "eng")
        XCTAssertTrue(importedWord.loanwordIsPartial)
        XCTAssertEqual(importedWord.reviewLogs.first?.typedAnswer, "かくに")
        XCTAssertEqual(importedWord.reviewLogs.first?.errorTypes, [.reading, .spelling])
    }

    func testImportingSameV2BackupWithMergeDoesNotCreateDuplicates() throws {
        let sourceContainer = try makeInMemoryTestContainer()
        try seedBackupFixture(in: sourceContainer.mainContext)
        let service = KotobaBackupService()
        let data = try service.exportBackup(in: sourceContainer.mainContext)
        let targetContainer = try makeInMemoryTestContainer()

        _ = try service.importBackup(from: data, strategy: .merge, in: targetContainer.mainContext)
        let second = try service.importBackup(from: data, strategy: .merge, in: targetContainer.mainContext)

        XCTAssertEqual(second.insertedWordBookCount, 0)
        XCTAssertEqual(second.insertedWordCount, 0)
        XCTAssertEqual(second.insertedProgressCount, 0)
        XCTAssertEqual(second.insertedReviewLogCount, 0)
        XCTAssertEqual(second.updatedCount, 0)
        XCTAssertGreaterThan(second.skippedCount, 0)
        XCTAssertEqual(try targetContainer.mainContext.fetchCount(FetchDescriptor<WordBook>()), 1)
        XCTAssertEqual(try targetContainer.mainContext.fetchCount(FetchDescriptor<VocabularyWord>()), 1)
        XCTAssertEqual(try targetContainer.mainContext.fetchCount(FetchDescriptor<LearningProgress>()), 1)
        XCTAssertEqual(try targetContainer.mainContext.fetchCount(FetchDescriptor<ReviewLog>()), 1)
    }

    func testLearningProgressExportUsesV3CoreFields() throws {
        let container = try makeInMemoryTestContainer()
        try seedBackupFixture(in: container.mainContext)
        let service = KotobaBackupService()
        let data = try service.exportLearningProgress(in: container.mainContext)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(KotobaLearningProgressExportFile.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, 3)
        XCTAssertEqual(decoded.learningProgress.first?.intervalDays, 4)
        XCTAssertEqual(decoded.reviewLogs.first?.errorTypes, [.reading, .spelling])
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("mastery"))
    }

    func testV1BackupImportsCoreDataAndIgnoresDeprecatedFieldsAndConjugations() throws {
        let service = KotobaBackupService()
        let targetContainer = try makeInMemoryTestContainer()
        let fixture = makeV1BackupFixture()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let result = try service.importBackup(
            from: encoder.encode(fixture.backup),
            strategy: .merge,
            in: targetContainer.mainContext
        )

        XCTAssertEqual(result.insertedWordBookCount, 1)
        XCTAssertEqual(result.insertedWordCount, 1)
        XCTAssertEqual(result.insertedProgressCount, 1)
        XCTAssertEqual(result.insertedReviewLogCount, 1)

        let word = try XCTUnwrap(targetContainer.mainContext.fetch(FetchDescriptor<VocabularyWord>()).first)
        let progress = try XCTUnwrap(word.progress)
        XCTAssertEqual(word.id, fixture.wordID)
        XCTAssertEqual(word.wordBook?.id, fixture.wordBookID)
        XCTAssertEqual(progress.state, .review)
        XCTAssertEqual(progress.dueAt, fixture.dueAt)
        XCTAssertEqual(progress.intervalDays, 60)
        XCTAssertEqual(progress.reviewCount, 12)
        XCTAssertEqual(progress.lapseCount, 2)
        XCTAssertEqual(word.reviewLogs.count, 1)
    }

    func testLegacyV2BackupWithoutEtymologyFieldsImportsWithSafeDefaults() throws {
        let source = try makeInMemoryTestContainer()
        try seedBackupFixture(in: source.mainContext)
        let service = KotobaBackupService()
        let currentData = try service.exportBackup(in: source.mainContext)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: currentData) as? [String: Any])
        json["schemaVersion"] = 2
        var words = try XCTUnwrap(json["vocabularyWords"] as? [[String: Any]])
        for index in words.indices {
            words[index].removeValue(forKey: "loanwordSourceTerm")
            words[index].removeValue(forKey: "loanwordSourceLanguageCode")
            words[index].removeValue(forKey: "loanwordIsWasei")
            words[index].removeValue(forKey: "loanwordIsPartial")
        }
        json["vocabularyWords"] = words
        let legacyData = try JSONSerialization.data(withJSONObject: json)
        let target = try makeInMemoryTestContainer()

        _ = try service.importBackup(from: legacyData, strategy: .merge, in: target.mainContext)
        let word = try XCTUnwrap(target.mainContext.fetch(FetchDescriptor<VocabularyWord>()).first)
        XCTAssertNil(word.loanwordSourceTerm)
        XCTAssertNil(word.loanwordSourceLanguageCode)
        XCTAssertFalse(word.loanwordIsWasei)
        XCTAssertFalse(word.loanwordIsPartial)
    }

    func testInvalidBackupDataDoesNotModifyDatabase() throws {
        let container = try makeInMemoryTestContainer()
        container.mainContext.insert(WordBook(name: "既有词书"))
        try container.mainContext.save()

        XCTAssertThrowsError(
            try KotobaBackupService().importBackup(
                from: Data("not-json".utf8),
                strategy: .merge,
                in: container.mainContext
            )
        )
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<WordBook>()), 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<VocabularyWord>()), 0)
    }

    func testSkipMergeAndOverwriteHaveDistinctConflictSemantics() throws {
        let source = try makeInMemoryTestContainer()
        try seedBackupFixture(in: source.mainContext)
        let service = KotobaBackupService()
        let data = try service.exportBackup(in: source.mainContext)
        let target = try makeInMemoryTestContainer()
        _ = try service.importBackup(from: data, strategy: .merge, in: target.mainContext)

        let word = try XCTUnwrap(target.mainContext.fetch(FetchDescriptor<VocabularyWord>()).first)
        let log = try XCTUnwrap(target.mainContext.fetch(FetchDescriptor<ReviewLog>()).first)
        word.chineseMeaning = "本地较新"
        word.updatedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        log.typedAnswer = "本地日志"
        try target.mainContext.save()

        let merge = try service.importBackup(from: data, strategy: .merge, in: target.mainContext)
        XCTAssertEqual(word.chineseMeaning, "本地较新")
        XCTAssertEqual(log.typedAnswer, "本地日志")
        XCTAssertGreaterThan(merge.skippedCount, 0)

        let overwrite = try service.importBackup(from: data, strategy: .overwriteByID, in: target.mainContext)
        XCTAssertEqual(word.chineseMeaning, "确认")
        XCTAssertEqual(log.typedAnswer, "かくに")
        XCTAssertGreaterThan(overwrite.updatedCount, 0)

        word.chineseMeaning = "跳过保留"
        try target.mainContext.save()
        let skip = try service.importBackup(from: data, strategy: .skipDuplicates, in: target.mainContext)
        XCTAssertEqual(word.chineseMeaning, "跳过保留")
        XCTAssertGreaterThan(skip.skippedCount, 0)
    }

    func testPreflightRejectsMissingReferencesWithoutChangingDatabase() throws {
        for (arrayName, referenceName) in [
            ("vocabularyWords", "wordBookID"),
            ("learningProgress", "wordID"),
            ("reviewLogs", "wordID")
        ] {
            try assertRejectedMutation { json in
                var rows = try XCTUnwrap(json[arrayName] as? [[String: Any]])
                rows[0][referenceName] = UUID().uuidString
                json[arrayName] = rows
            }
        }
    }

    func testPreflightRejectsDuplicateEntityIDsAndMultipleProgress() throws {
        for arrayName in ["wordBooks", "vocabularyWords", "learningProgress", "reviewLogs"] {
            try assertRejectedMutation { json in
                var rows = try XCTUnwrap(json[arrayName] as? [[String: Any]])
                rows.append(rows[0])
                json[arrayName] = rows
            }
        }

        try assertRejectedMutation { json in
            var rows = try XCTUnwrap(json["learningProgress"] as? [[String: Any]])
            var second = rows[0]
            second["id"] = UUID().uuidString
            rows.append(second)
            json["learningProgress"] = rows
        }
    }

    func testPreflightRejectsBlankRequiredWordFieldsWithoutChangingDatabase() throws {
        for field in ["japanese", "kana", "chineseMeaning"] {
            try assertRejectedMutation { json in
                var rows = try XCTUnwrap(json["vocabularyWords"] as? [[String: Any]])
                rows[0][field] = "  \n "
                json["vocabularyWords"] = rows
            }
        }
    }

    func testMergeRejectsIncomingProgressThatWouldCreateSecondProgressForLocalWord() throws {
        let source = try makeInMemoryTestContainer()
        _ = try seedBackupFixture(in: source.mainContext)
        let service = KotobaBackupService()
        let data = try service.exportBackup(in: source.mainContext)
        let decoded = try service.decodeBackup(from: data)
        let target = try makeInMemoryTestContainer()
        _ = try service.importBackup(from: data, strategy: .merge, in: target.mainContext)

        var conflicting = decoded
        let existing = try XCTUnwrap(conflicting.learningProgress.first)
        conflicting.learningProgress = [
            BackupLearningProgress(
                id: UUID(),
                wordID: existing.wordID,
                state: existing.state,
                dueAt: existing.dueAt,
                intervalDays: existing.intervalDays,
                reviewCount: existing.reviewCount,
                lapseCount: existing.lapseCount,
                lastReviewedAt: existing.lastReviewedAt,
                createdAt: existing.createdAt,
                updatedAt: existing.updatedAt
            )
        ]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let countsBefore = try persistentCounts(in: target.mainContext)

        XCTAssertThrowsError(
            try service.importBackup(from: encoder.encode(conflicting), strategy: .merge, in: target.mainContext)
        )
        XCTAssertEqual(try persistentCounts(in: target.mainContext), countsBefore)
    }

    @discardableResult
    private func seedBackupFixture(in context: ModelContext) throws -> BackupFixtureIDs {
        let wordBookID = UUID()
        let wordID = UUID()
        let baseDate = Date(timeIntervalSinceReferenceDate: 10)
        let dueAt = baseDate.addingTimeInterval(4 * 86_400)
        let wordBook = WordBook(
            id: wordBookID,
            name: "测试词书",
            bookDescription: "备份测试",
            createdAt: baseDate,
            updatedAt: baseDate
        )
        let word = VocabularyWord(
            id: wordID,
            japanese: "確認",
            kana: "かくにん",
            chineseMeaning: "确认",
            partOfSpeech: "名词/サ变动词",
            jlptLevel: "N3",
            exampleJapanese: "予約を確認します。",
            exampleChinese: "确认预约。",
            tags: ["工作"],
            createdAt: baseDate,
            updatedAt: baseDate,
            isFavorite: true,
            loanwordSourceTerm: "computer",
            loanwordSourceLanguageCode: "eng",
            loanwordIsPartial: true,
            wordBook: wordBook
        )
        let progress = LearningProgress(
            state: .review,
            dueAt: dueAt,
            intervalDays: 4,
            reviewCount: 6,
            lapseCount: 1,
            lastReviewedAt: baseDate,
            createdAt: baseDate,
            updatedAt: baseDate,
            word: word
        )
        let log = ReviewLog(
            reviewedAt: baseDate,
            rating: .hard,
            previousState: .review,
            nextState: .review,
            previousIntervalDays: 2,
            nextIntervalDays: 4,
            scheduledDueAt: dueAt,
            errorTypes: [.reading, .spelling],
            typedAnswer: "かくに",
            expectedAnswer: "かくにん",
            readingWrongCount: 1,
            spellingWrongCount: 1,
            word: word
        )

        word.progress = progress
        word.reviewLogs.append(log)
        context.insert(wordBook)
        context.insert(word)
        context.insert(progress)
        context.insert(log)
        try context.save()
        return BackupFixtureIDs(wordBookID: wordBookID, wordID: wordID, dueAt: dueAt)
    }

    private func assertRejectedMutation(
        _ mutation: (inout [String: Any]) throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makeInMemoryTestContainer()
        _ = try seedBackupFixture(in: source.mainContext)
        let service = KotobaBackupService()
        let validData = try service.exportBackup(in: source.mainContext)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: validData) as? [String: Any])
        try mutation(&json)
        let malformedData = try JSONSerialization.data(withJSONObject: json)

        let target = try makeInMemoryTestContainer()
        let existingBook = WordBook(name: "导入前已有")
        target.mainContext.insert(existingBook)
        try target.mainContext.save()
        let countsBefore = try persistentCounts(in: target.mainContext)

        XCTAssertThrowsError(
            try service.importBackup(from: malformedData, strategy: .merge, in: target.mainContext),
            file: file,
            line: line
        )
        XCTAssertEqual(try persistentCounts(in: target.mainContext), countsBefore, file: file, line: line)
    }

    private func persistentCounts(in context: ModelContext) throws -> [Int] {
        [
            try context.fetchCount(FetchDescriptor<WordBook>()),
            try context.fetchCount(FetchDescriptor<VocabularyWord>()),
            try context.fetchCount(FetchDescriptor<LearningProgress>()),
            try context.fetchCount(FetchDescriptor<ReviewLog>())
        ]
    }

    private func makeV1BackupFixture() -> V1BackupFixture {
        let wordBookID = UUID()
        let wordID = UUID()
        let progressID = UUID()
        let logID = UUID()
        let date = Date(timeIntervalSinceReferenceDate: 20_000)
        let dueAt = date.addingTimeInterval(60 * 86_400)
        let book = BackupWordBook(
            id: wordBookID,
            name: "旧备份词书",
            bookDescription: "V1",
            createdAt: date,
            updatedAt: date,
            isBuiltIn: false
        )
        let word = BackupVocabularyWord(
            id: wordID,
            japanese: "食べる",
            kana: "たべる",
            chineseMeaning: "吃",
            partOfSpeech: "一段动词",
            jlptLevel: "N5",
            exampleJapanese: "ご飯を食べる。",
            exampleChinese: "吃饭。",
            tags: ["用户编辑"],
            createdAt: date,
            updatedAt: date,
            isArchived: false,
            isFavorite: true,
            wordBookID: wordBookID
        )
        let progress = BackupLearningProgressV1(
            id: progressID,
            wordID: wordID,
            state: .review,
            dueAt: dueAt,
            intervalDays: 60,
            reviewLevel: 8,
            reviewCount: 12,
            lapseCount: 2,
            totalCorrectCount: 99,
            totalWrongCount: 7,
            consecutivePerfectCount: 3,
            consecutiveWrongCount: 1,
            meaningMastery: 3,
            readingMastery: 3,
            spellingMastery: 2,
            conjugationMastery: 3,
            firstLearnedAt: date,
            lastReviewedAt: date,
            createdAt: date,
            updatedAt: date
        )
        let log = BackupReviewLogV1(
            id: logID,
            wordID: wordID,
            reviewedAt: date,
            rating: .easy,
            previousState: .review,
            nextState: .review,
            previousIntervalDays: 30,
            nextIntervalDays: 60,
            scheduledDueAt: dueAt,
            errorTypes: [.conjugation],
            typedAnswer: nil,
            expectedAnswer: nil,
            questionDirectionRawValue: nil,
            formTypeRawValue: nil,
            reviewLevelBefore: 7,
            reviewLevelAfter: 8,
            readingWrongCount: 0,
            spellingWrongCount: 0,
            conjugationWrongCount: 0,
            repeatedWrongCount: 0
        )
        let conjugation = BackupConjugationRecordV1(
            id: UUID(),
            wordID: wordID,
            conjugationClass: .ichidanVerb,
            source: "lmStudio",
            validationStatus: "valid",
            forms: [ConjugationForm(type: .polite, surface: "食べます", reading: "たべます")],
            modelName: "legacy",
            generatedAt: date,
            schemaVersion: 1,
            sourceFingerprint: "legacy",
            markedIncorrect: false
        )
        return V1BackupFixture(
            backup: KotobaBackupFileV1(
                appVersion: "1.0",
                schemaVersion: 1,
                exportedAt: date,
                wordBooks: [book],
                vocabularyWords: [word],
                learningProgress: [progress],
                reviewLogs: [log],
                conjugationRecords: [conjugation]
            ),
            wordBookID: wordBookID,
            wordID: wordID,
            dueAt: dueAt
        )
    }
}

private struct BackupFixtureIDs {
    let wordBookID: UUID
    let wordID: UUID
    let dueAt: Date
}

private struct V1BackupFixture {
    let backup: KotobaBackupFileV1
    let wordBookID: UUID
    let wordID: UUID
    let dueAt: Date
}
