//
//  KotobaBackupImporterTests.swift
//  KotobaTests
//

import SwiftData
import XCTest
@testable import Kotoba

@MainActor
final class KotobaBackupImporterTests: XCTestCase {
    func testBackgroundImportSucceedsAndMainContextObservesSavedResult() async throws {
        let container = try makeInMemoryTestContainer()
        let backup = makeBackup(meaning: "后台导入")
        let data = try KotobaBackupService.encodeBackupSnapshot(backup)
        let importer = KotobaBackupImportCoordinator(modelContainer: container)

        let result = try await importer.importBackup(from: data, strategy: .merge)

        XCTAssertEqual(result.insertedWordBookCount, 1)
        XCTAssertEqual(result.insertedWordCount, 1)
        XCTAssertEqual(result.insertedProgressCount, 1)
        XCTAssertEqual(result.insertedReviewLogCount, 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<WordBook>()), 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<VocabularyWord>()), 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<LearningProgress>()), 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ReviewLog>()), 1)
        XCTAssertEqual(
            try container.mainContext.fetch(FetchDescriptor<VocabularyWord>()).first?.chineseMeaning,
            "后台导入"
        )
    }

    func testBackgroundInvalidBackupLeavesStoreUnchanged() async throws {
        let container = try makeInMemoryTestContainer()
        let backup = makeBackup(meaning: "无效", referencedBookID: UUID())
        let data = try KotobaBackupService.encodeBackupSnapshot(backup)
        let importer = KotobaBackupImportCoordinator(modelContainer: container)

        do {
            _ = try await importer.importBackup(from: data, strategy: .merge)
            XCTFail("Expected missing relationship to be rejected")
        } catch {
            XCTAssertTrue(error is KotobaBackupValidationError)
        }

        XCTAssertEqual(try persistentCounts(in: container.mainContext), [0, 0, 0, 0])
    }

    func testBackgroundSaveFailureRollsBackAppliedChanges() async throws {
        let container = try makeInMemoryTestContainer()
        let data = try KotobaBackupService.encodeBackupSnapshot(makeBackup(meaning: "不会保存"))
        let importer = KotobaBackupImportCoordinator(
            modelContainer: container,
            beforeSave: { throw InjectedBackupFailure.expected }
        )

        do {
            _ = try await importer.importBackup(from: data, strategy: .merge)
            XCTFail("Expected injected persistence failure")
        } catch {
            XCTAssertEqual(error as? InjectedBackupFailure, .expected)
        }

        XCTAssertEqual(try persistentCounts(in: container.mainContext), [0, 0, 0, 0])
    }

    func testAllConflictStrategiesUseBackgroundPathWithoutDuplicateProgressOrLogs() async throws {
        for strategy in KotobaBackupImportStrategy.allCases {
            let container = try makeInMemoryTestContainer()
            let importer = KotobaBackupImportCoordinator(modelContainer: container)
            let local = makeBackup(
                meaning: "本地",
                updatedAt: Date(timeIntervalSinceReferenceDate: 100),
                typedAnswer: "本地日志"
            )
            let incoming = makeBackup(
                meaning: "传入",
                updatedAt: Date(timeIntervalSinceReferenceDate: 200),
                typedAnswer: "传入日志"
            )

            _ = try await importer.importBackup(
                from: KotobaBackupService.encodeBackupSnapshot(local),
                strategy: .merge
            )
            _ = try await importer.importBackup(
                from: KotobaBackupService.encodeBackupSnapshot(incoming),
                strategy: strategy
            )

            let freshContext = ModelContext(container)
            let word = try XCTUnwrap(freshContext.fetch(FetchDescriptor<VocabularyWord>()).first)
            let log = try XCTUnwrap(freshContext.fetch(FetchDescriptor<ReviewLog>()).first)
            switch strategy {
            case .merge:
                XCTAssertEqual(word.chineseMeaning, "传入")
                XCTAssertEqual(log.typedAnswer, "本地日志")
            case .skipDuplicates:
                XCTAssertEqual(word.chineseMeaning, "本地")
                XCTAssertEqual(log.typedAnswer, "本地日志")
            case .overwriteByID:
                XCTAssertEqual(word.chineseMeaning, "传入")
                XCTAssertEqual(log.typedAnswer, "传入日志")
            }
            XCTAssertEqual(try freshContext.fetchCount(FetchDescriptor<LearningProgress>()), 1)
            XCTAssertEqual(try freshContext.fetchCount(FetchDescriptor<ReviewLog>()), 1)
        }
    }

    func testConcurrentSecondImportIsRejectedWhileFirstOwnsStoreOperation() async throws {
        let container = try makeInMemoryTestContainer()
        let gate = BackupImportGate()
        let importer = KotobaBackupImportCoordinator(
            modelContainer: container,
            beforeImport: { await gate.wait() }
        )
        let data = try KotobaBackupService.encodeBackupSnapshot(makeBackup(meaning: "single flight"))

        let first = Task { try await importer.importBackup(from: data, strategy: .merge) }
        await gate.waitUntilEntered()

        do {
            _ = try await importer.importBackup(from: data, strategy: .merge)
            XCTFail("Expected concurrent import to be rejected")
        } catch {
            XCTAssertEqual(error as? KotobaBackupImportError, .alreadyInProgress)
        }

        await gate.open()
        _ = try await first.value
    }

    func testMainActorRemainsSchedulableWhileBackgroundImportIsActive() async throws {
        let container = try makeInMemoryTestContainer()
        let gate = BackupImportGate()
        let importer = KotobaBackupImportCoordinator(
            modelContainer: container,
            beforeImport: { await gate.wait() }
        )
        let data = try KotobaBackupService.encodeBackupSnapshot(makeBackup(meaning: "responsive"))
        let importTask = Task { try await importer.importBackup(from: data, strategy: .merge) }
        await gate.waitUntilEntered()

        let heartbeat = expectation(description: "MainActor heartbeat")
        Task { @MainActor in heartbeat.fulfill() }
        await fulfillment(of: [heartbeat], timeout: 0.2)
        let importIsActive = await importer.hasImportInProgress()
        XCTAssertTrue(importIsActive)

        await gate.open()
        _ = try await importTask.value
    }

    private func makeBackup(
        meaning: String,
        updatedAt: Date = Date(timeIntervalSinceReferenceDate: 100),
        typedAnswer: String = "answer",
        referencedBookID: UUID? = nil
    ) -> KotobaBackupFile {
        let bookID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
        let wordID = UUID(uuidString: "10000000-0000-4000-8000-000000000002")!
        let progressID = UUID(uuidString: "10000000-0000-4000-8000-000000000003")!
        let logID = UUID(uuidString: "10000000-0000-4000-8000-000000000004")!
        let createdAt = Date(timeIntervalSinceReferenceDate: 50)

        return KotobaBackupFile(
            appVersion: "test",
            schemaVersion: KotobaBackupService.schemaVersion,
            exportedAt: updatedAt,
            wordBooks: [
                BackupWordBook(
                    id: bookID,
                    name: "后台词书",
                    bookDescription: "",
                    createdAt: createdAt,
                    updatedAt: updatedAt,
                    isBuiltIn: false
                )
            ],
            vocabularyWords: [
                BackupVocabularyWord(
                    id: wordID,
                    japanese: "確認",
                    kana: "かくにん",
                    chineseMeaning: meaning,
                    partOfSpeech: "名词",
                    jlptLevel: "N3",
                    exampleJapanese: "確認します。",
                    exampleChinese: "进行确认。",
                    tags: [],
                    createdAt: createdAt,
                    updatedAt: updatedAt,
                    isArchived: false,
                    isFavorite: false,
                    wordBookID: referencedBookID ?? bookID
                )
            ],
            learningProgress: [
                BackupLearningProgress(
                    id: progressID,
                    wordID: wordID,
                    state: .review,
                    dueAt: updatedAt,
                    intervalDays: 2,
                    reviewCount: 1,
                    lapseCount: 0,
                    lastReviewedAt: updatedAt,
                    createdAt: createdAt,
                    updatedAt: updatedAt
                )
            ],
            reviewLogs: [
                BackupReviewLog(
                    id: logID,
                    wordID: wordID,
                    reviewedAt: updatedAt,
                    rating: .good,
                    previousState: .new,
                    nextState: .review,
                    previousIntervalDays: 0,
                    nextIntervalDays: 2,
                    scheduledDueAt: updatedAt,
                    errorTypes: [],
                    typedAnswer: typedAnswer,
                    expectedAnswer: "確認",
                    questionDirectionRawValue: nil,
                    readingWrongCount: 0,
                    spellingWrongCount: 0,
                    repeatedWrongCount: 0
                )
            ]
        )
    }

    private func persistentCounts(in context: ModelContext) throws -> [Int] {
        [
            try context.fetchCount(FetchDescriptor<WordBook>()),
            try context.fetchCount(FetchDescriptor<VocabularyWord>()),
            try context.fetchCount(FetchDescriptor<LearningProgress>()),
            try context.fetchCount(FetchDescriptor<ReviewLog>())
        ]
    }
}

private enum InjectedBackupFailure: Error, Equatable, Sendable {
    case expected
}

private actor BackupImportGate {
    private var entered = false
    private var isOpen = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        entered = true
        guard !isOpen else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilEntered() async {
        while !entered {
            await Task.yield()
        }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
