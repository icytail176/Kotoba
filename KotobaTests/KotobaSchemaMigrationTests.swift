//
//  KotobaSchemaMigrationTests.swift
//  KotobaTests
//

import SwiftData
import XCTest
@testable import Kotoba

@MainActor
final class KotobaSchemaMigrationTests: XCTestCase {
    func testV1ToV2PreservesNewWord() throws {
        let fixture = try makeMigratedFixture()
        let word = try migratedWord(named: "新しい", in: fixture.container)
        XCTAssertEqual(word.progress?.state, .new)
        XCTAssertEqual(word.progress?.intervalDays, 0)
        XCTAssertEqual(word.progress?.dueAt, fixture.expected["新しい"]?.dueAt)
    }

    func testV1ToV2PreservesSixtyDayReviewWord() throws {
        let fixture = try makeMigratedFixture()
        let word = try migratedWord(named: "六十日", in: fixture.container)
        XCTAssertEqual(word.progress?.state, .review)
        XCTAssertEqual(word.progress?.intervalDays, 60)
        XCTAssertEqual(word.progress?.dueAt, fixture.expected["六十日"]?.dueAt)
    }

    func testV1ToV2PreservesTenMinuteRelearningWord() throws {
        let fixture = try makeMigratedFixture()
        let word = try migratedWord(named: "再学習", in: fixture.container)
        XCTAssertEqual(word.progress?.state, .relearning)
        XCTAssertEqual(word.progress?.intervalDays, 0)
        XCTAssertEqual(word.progress?.dueAt, fixture.expected["再学習"]?.dueAt)
    }

    func testV1ToV2PreservesLargeReviewLogHistory() throws {
        let fixture = try makeMigratedFixture(reviewLogCount: 80)
        XCTAssertEqual(try fixture.container.mainContext.fetchCount(FetchDescriptor<ReviewLog>()), 80)
    }

    func testV1ToV2PreservesFavorite() throws {
        let fixture = try makeMigratedFixture()
        XCTAssertTrue(try migratedWord(named: "お気に入り", in: fixture.container).isFavorite)
    }

    func testV1ToV2PreservesUserEditedVocabulary() throws {
        let fixture = try makeMigratedFixture()
        let word = try migratedWord(named: "編集済み", in: fixture.container)
        XCTAssertEqual(word.kana, "へんしゅうずみ")
        XCTAssertEqual(word.chineseMeaning, "用户修改后的释义")
        XCTAssertEqual(word.exampleJapanese, "これは利用者が編集した例文です。")
        XCTAssertEqual(word.tags, ["用户", "编辑"])
    }

    func testV1WithConjugationRecordMigratesToFourModelV2Schema() throws {
        let fixture = try makeMigratedFixture()
        XCTAssertEqual(
            Set(fixture.container.schema.entities.map(\.name)),
            Set(["WordBook", "VocabularyWord", "LearningProgress", "ReviewLog"])
        )
    }

    func testV1WithSpeechTuningRecordMigratesToFourModelV2Schema() throws {
        let fixture = try makeMigratedFixture()
        XCTAssertFalse(fixture.container.schema.entities.map(\.name).contains("SpeechTuningRecord"))
        XCTAssertEqual(try fixture.container.mainContext.fetchCount(FetchDescriptor<VocabularyWord>()), 10)
    }

    func testV1ToV2PreservesCountsAndEveryCoreSchedulingFieldExactly() throws {
        let fixture = try makeMigratedFixture(reviewLogCount: 50)
        let context = fixture.container.mainContext
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WordBook>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<VocabularyWord>()), 10)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LearningProgress>()), 10)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReviewLog>()), 50)

        for word in try context.fetch(FetchDescriptor<VocabularyWord>()) {
            let expected = try XCTUnwrap(fixture.expected[word.japanese])
            let progress = try XCTUnwrap(word.progress)
            XCTAssertEqual(word.id, expected.wordID)
            XCTAssertEqual(word.wordBook?.id, expected.bookID)
            XCTAssertEqual(progress.state, expected.state)
            XCTAssertEqual(progress.dueAt, expected.dueAt)
            XCTAssertEqual(progress.intervalDays, expected.intervalDays)
            XCTAssertEqual(progress.reviewCount, expected.reviewCount)
            XCTAssertEqual(progress.lapseCount, expected.lapseCount)
            XCTAssertEqual(progress.lastReviewedAt, expected.lastReviewedAt)
            XCTAssertNil(word.loanwordSourceTerm)
            XCTAssertNil(word.loanwordSourceLanguageCode)
            XCTAssertFalse(word.loanwordIsWasei)
            XCTAssertFalse(word.loanwordIsPartial)
        }
    }

    func testV2DiskStoreMigratesToV3WithoutChangingCoreData() throws {
        let directory = try makeTemporaryDirectory()
        let storeURL = directory.appendingPathComponent("v2.store")
        let expected = try createV2Store(at: storeURL)
        let container = try KotobaStore.makeContainer(at: storeURL)
        let word = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<VocabularyWord>()).first)
        let progress = try XCTUnwrap(word.progress)

        XCTAssertEqual(word.id, expected.wordID)
        XCTAssertEqual(word.wordBook?.id, expected.bookID)
        XCTAssertTrue(word.isFavorite)
        XCTAssertEqual(progress.state, .review)
        XCTAssertEqual(progress.dueAt, expected.dueAt)
        XCTAssertEqual(progress.intervalDays, 30)
        XCTAssertEqual(progress.reviewCount, 9)
        XCTAssertEqual(progress.lapseCount, 2)
        XCTAssertEqual(word.reviewLogs.count, 1)
        XCTAssertNil(word.loanwordSourceTerm)
        XCTAssertNil(word.loanwordSourceLanguageCode)
        XCTAssertFalse(word.loanwordIsWasei)
        XCTAssertFalse(word.loanwordIsPartial)
    }

    func testDefaultStoreUsesAnAppSpecificDirectoryInsteadOfTheSharedDefaultName() {
        XCTAssertEqual(KotobaStore.defaultStoreURL.lastPathComponent, "Kotoba.store")
        XCTAssertEqual(KotobaStore.defaultStoreURL.deletingLastPathComponent().lastPathComponent, "Kotoba")
        XCTAssertNotEqual(KotobaStore.defaultStoreURL, KotobaStore.legacyDefaultStoreURL)
    }

    func testLegacyKotobaStoreIsCopiedWithoutDeletingTheOriginal() throws {
        let directory = try makeTemporaryDirectory()
        let legacyURL = directory.appendingPathComponent("default.store")
        let destinationURL = directory
            .appendingPathComponent("Kotoba", isDirectory: true)
            .appendingPathComponent("Kotoba.store")
        let expected = try createV2Store(at: legacyURL)

        XCTAssertTrue(KotobaStore.isLegacyKotobaStore(at: legacyURL))
        try KotobaStore.copyLegacyStoreFamilyIfNeeded(from: legacyURL, to: destinationURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))

        let migrated = try KotobaStore.makeContainer(at: destinationURL)
        let word = try XCTUnwrap(migrated.mainContext.fetch(FetchDescriptor<VocabularyWord>()).first)
        XCTAssertEqual(word.id, expected.wordID)
        XCTAssertEqual(word.wordBook?.id, expected.bookID)
        XCTAssertNil(word.loanwordSourceTerm)
    }

    func testUnrelatedLegacyStoreIsIgnored() throws {
        let directory = try makeTemporaryDirectory()
        let unrelatedURL = directory.appendingPathComponent("default.store")
        let destinationURL = directory.appendingPathComponent("Kotoba.store")
        try Data("not-a-kotoba-store".utf8).write(to: unrelatedURL)

        XCTAssertFalse(KotobaStore.isLegacyKotobaStore(at: unrelatedURL))
        try KotobaStore.copyLegacyStoreFamilyIfNeeded(from: unrelatedURL, to: destinationURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
        XCTAssertEqual(try Data(contentsOf: unrelatedURL), Data("not-a-kotoba-store".utf8))
    }

    func testMigrationFailureDoesNotReplaceInvalidStoreWithEmptyDatabase() throws {
        let directory = try makeTemporaryDirectory()
        let storeURL = directory.appendingPathComponent("corrupt.store")
        let original = Data("not-a-sqlite-store".utf8)
        try original.write(to: storeURL)

        XCTAssertThrowsError(try KotobaStore.makeContainer(at: storeURL))
        XCTAssertEqual(try Data(contentsOf: storeURL), original)
    }

    func testMigrationBackupCopiesStoreWALAndSHMAsOneFamily() throws {
        let directory = try makeTemporaryDirectory()
        let storeURL = directory.appendingPathComponent("default.store")
        let family = [storeURL, URL(fileURLWithPath: storeURL.path + "-wal"), URL(fileURLWithPath: storeURL.path + "-shm")]
        for (index, url) in family.enumerated() {
            try Data("file-\(index)".utf8).write(to: url)
        }
        let backupRoot = directory.appendingPathComponent("backups", isDirectory: true)

        let destination = try XCTUnwrap(
            KotobaStore.backUpStoreFamilyIfPresent(at: storeURL, backupRootOverride: backupRoot)
        )

        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: destination.path)), Set(family.map(\.lastPathComponent)))
        for url in family {
            XCTAssertEqual(
                try Data(contentsOf: destination.appendingPathComponent(url.lastPathComponent)),
                try Data(contentsOf: url)
            )
        }
    }

    func testAnyStoreFamilyBackupFailureIsPropagatedBeforeMigrationCanStart() throws {
        enum FixtureError: Error { case copyFailed }
        let directory = try makeTemporaryDirectory()
        let storeURL = directory.appendingPathComponent("default.store")
        try Data("store".utf8).write(to: storeURL)
        try Data("wal".utf8).write(to: URL(fileURLWithPath: storeURL.path + "-wal"))
        XCTAssertThrowsError(
            try KotobaStore.backUpStoreFamilyIfPresent(
                at: storeURL,
                backupRootOverride: directory.appendingPathComponent("backups", isDirectory: true),
                copyItem: { source, target in
                    if source.lastPathComponent.hasSuffix("-wal") { throw FixtureError.copyFailed }
                    try FileManager.default.copyItem(at: source, to: target)
                }
            )
        )
    }

    private func makeMigratedFixture(reviewLogCount: Int = 50) throws -> MigratedFixture {
        let directory = try makeTemporaryDirectory()
        let storeURL = directory.appendingPathComponent("fixture.store")
        let expected = try createV1Store(at: storeURL, reviewLogCount: reviewLogCount)
        let container = try KotobaStore.makeContainer(at: storeURL)
        return MigratedFixture(container: container, expected: expected)
    }

    private func createV2Store(at storeURL: URL) throws -> (wordID: UUID, bookID: UUID, dueAt: Date) {
        let schema = Schema(versionedSchema: KotobaSchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let dueAt = now.addingTimeInterval(30 * 86_400)
        let book = KotobaSchemaV2.WordBook(name: "JLPT N5", createdAt: now, updatedAt: now, isBuiltIn: true)
        let word = KotobaSchemaV2.VocabularyWord(
            japanese: "コンピューター",
            kana: "コンピューター",
            chineseMeaning: "电脑",
            partOfSpeech: "名词",
            jlptLevel: "N5",
            createdAt: now,
            updatedAt: now,
            isFavorite: true,
            wordBook: book
        )
        let progress = KotobaSchemaV2.LearningProgress(
            state: .review,
            dueAt: dueAt,
            intervalDays: 30,
            reviewCount: 9,
            lapseCount: 2,
            lastReviewedAt: now,
            createdAt: now,
            updatedAt: now,
            word: word
        )
        let log = KotobaSchemaV2.ReviewLog(
            reviewedAt: now,
            rating: .good,
            previousState: .review,
            nextState: .review,
            previousIntervalDays: 15,
            nextIntervalDays: 30,
            scheduledDueAt: dueAt,
            word: word
        )
        word.progress = progress
        word.reviewLogs.append(log)
        context.insert(book)
        context.insert(word)
        context.insert(progress)
        context.insert(log)
        try context.save()
        return (word.id, book.id, dueAt)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KotobaMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func createV1Store(
        at storeURL: URL,
        reviewLogCount: Int
    ) throws -> [String: ExpectedProgress] {
        let schema = Schema(versionedSchema: KotobaSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let baseDate = Date(timeIntervalSinceReferenceDate: 900_000_000)
        let builtInBook = KotobaSchemaV1.WordBook(
            id: UUID(),
            name: "JLPT N5",
            createdAt: baseDate,
            updatedAt: baseDate,
            isBuiltIn: true
        )
        let userBook = KotobaSchemaV1.WordBook(
            id: UUID(),
            name: "用户词书",
            bookDescription: "不得丢失",
            createdAt: baseDate,
            updatedAt: baseDate
        )
        context.insert(builtInBook)
        context.insert(userBook)

        let specifications: [(String, LearningState, Int, TimeInterval, Bool, Bool)] = [
            ("新しい", .new, 0, 0, false, true),
            ("再学習", .relearning, 0, 600, false, true),
            ("一日", .learning, 1, 86_400, false, true),
            ("二日", .review, 2, 2 * 86_400, false, true),
            ("四日", .review, 4, 4 * 86_400, false, true),
            ("七日", .review, 7, 7 * 86_400, false, true),
            ("十五日", .review, 15, 15 * 86_400, false, true),
            ("お気に入り", .review, 30, 30 * 86_400, true, false),
            ("編集済み", .review, 45, 45 * 86_400, false, false),
            ("六十日", .review, 60, 60 * 86_400, false, false)
        ]
        var expected: [String: ExpectedProgress] = [:]
        var words: [KotobaSchemaV1.VocabularyWord] = []

        for (index, item) in specifications.enumerated() {
            let book = item.5 ? builtInBook : userBook
            let wordID = UUID()
            let dueAt = baseDate.addingTimeInterval(item.3)
            let lastReviewedAt = item.1 == .new ? nil : baseDate.addingTimeInterval(-Double(index + 1) * 3_600)
            let word = KotobaSchemaV1.VocabularyWord(
                id: wordID,
                japanese: item.0,
                kana: item.0 == "編集済み" ? "へんしゅうずみ" : "かな\(index)",
                chineseMeaning: item.0 == "編集済み" ? "用户修改后的释义" : "释义\(index)",
                partOfSpeech: "名词",
                jlptLevel: "N5",
                exampleJapanese: item.0 == "編集済み" ? "これは利用者が編集した例文です。" : "例文\(index)",
                exampleChinese: "例句\(index)",
                tags: item.0 == "編集済み" ? ["用户", "编辑"] : ["fixture"],
                createdAt: baseDate.addingTimeInterval(Double(index)),
                updatedAt: baseDate,
                isFavorite: item.4,
                wordBook: book
            )
            let progress = KotobaSchemaV1.LearningProgress(
                id: UUID(),
                state: item.1,
                dueAt: dueAt,
                intervalDays: item.2,
                reviewLevel: 8,
                reviewCount: index,
                lapseCount: index % 3,
                totalCorrectCount: 100 + index,
                totalWrongCount: 20 + index,
                consecutivePerfectCount: 4,
                consecutiveWrongCount: 2,
                meaningMastery: 3,
                readingMastery: 2,
                spellingMastery: 1,
                conjugationMastery: 3,
                firstLearnedAt: baseDate.addingTimeInterval(-100_000),
                lastReviewedAt: lastReviewedAt,
                createdAt: baseDate,
                updatedAt: baseDate,
                word: word
            )
            word.progress = progress
            book.words.append(word)
            context.insert(word)
            context.insert(progress)
            words.append(word)
            expected[item.0] = ExpectedProgress(
                wordID: wordID,
                bookID: book.id,
                state: item.1,
                dueAt: dueAt,
                intervalDays: item.2,
                reviewCount: index,
                lapseCount: index % 3,
                lastReviewedAt: lastReviewedAt
            )
        }

        for index in 0..<reviewLogCount {
            let word = words[index % words.count]
            let log = KotobaSchemaV1.ReviewLog(
                id: UUID(),
                reviewedAt: baseDate.addingTimeInterval(Double(index)),
                rating: index % 4 == 0 ? .again : .good,
                previousState: .review,
                nextState: .review,
                previousIntervalDays: 7,
                nextIntervalDays: 15,
                scheduledDueAt: baseDate.addingTimeInterval(15 * 86_400),
                errorTypesRawValue: index % 2 == 0 ? "spelling" : "",
                typedAnswer: index % 2 == 0 ? "誤答" : nil,
                expectedAnswer: index % 2 == 0 ? word.japanese : nil,
                reviewLevelBefore: 7,
                reviewLevelAfter: 8,
                spellingWrongCount: index % 2,
                word: word
            )
            word.reviewLogs.append(log)
            context.insert(log)
        }

        context.insert(
            KotobaSchemaV1.ConjugationRecord(
                wordID: words[0].id,
                conjugationClassRawValue: "ichidanVerb",
                sourceRawValue: "lmStudio",
                validationStatusRawValue: "valid",
                modelName: "legacy",
                sourceFingerprint: "legacy"
            )
        )
        context.insert(
            KotobaSchemaV1.SpeechTuningRecord(
                wordID: words[0].id,
                wordBookID: builtInBook.id,
                speakerID: 3,
                baseText: words[0].japanese,
                audioQueryJSON: Data("{}".utf8),
                isManualEdited: true
            )
        )
        try context.save()
        return expected
    }

    private func migratedWord(named name: String, in container: ModelContainer) throws -> VocabularyWord {
        try XCTUnwrap(
            container.mainContext.fetch(FetchDescriptor<VocabularyWord>()).first { $0.japanese == name }
        )
    }
}

private struct ExpectedProgress {
    let wordID: UUID
    let bookID: UUID
    let state: LearningState
    let dueAt: Date
    let intervalDays: Int
    let reviewCount: Int
    let lapseCount: Int
    let lastReviewedAt: Date?
}

private struct MigratedFixture {
    let container: ModelContainer
    let expected: [String: ExpectedProgress]
}
