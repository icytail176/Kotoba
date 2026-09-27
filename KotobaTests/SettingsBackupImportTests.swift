//
//  SettingsBackupImportTests.swift
//  KotobaTests
//

import XCTest
@testable import Kotoba

@MainActor
final class SettingsBackupImportTests: XCTestCase {
    func testImportingStateIsTrueUntilSuccessThenClears() async throws {
        let container = try makeInMemoryTestContainer()
        let importer = ControlledBackupImporter()
        let viewModel = SettingsViewModel(backupImporter: importer)
        try viewModel.stageBackupImport(data: try validBackupData())

        viewModel.confirmBackupImport(context: container.mainContext)

        XCTAssertTrue(viewModel.isImportingBackup)
        XCTAssertEqual(viewModel.backupImportStatus, "正在导入备份…")
        await importer.waitUntilStarted()
        XCTAssertTrue(viewModel.isImportingBackup)

        await importer.succeed()
        await waitUntil { !viewModel.isImportingBackup }

        XCTAssertNil(viewModel.backupImportStatus)
        XCTAssertFalse(viewModel.isBackupImportConfirmationPresented)
        XCTAssertNotNil(viewModel.successMessage)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testImportingStateClearsAndErrorPropagatesAfterFailure() async throws {
        let container = try makeInMemoryTestContainer()
        let importer = ControlledBackupImporter()
        let viewModel = SettingsViewModel(backupImporter: importer)
        try viewModel.stageBackupImport(data: try validBackupData())

        viewModel.confirmBackupImport(context: container.mainContext)
        await importer.waitUntilStarted()
        await importer.fail()
        await waitUntil { !viewModel.isImportingBackup }

        XCTAssertNil(viewModel.backupImportStatus)
        XCTAssertTrue(viewModel.isBackupImportConfirmationPresented)
        XCTAssertNil(viewModel.successMessage)
        XCTAssertTrue(viewModel.errorMessage?.contains("备份导入失败") == true)
    }

    func testRapidRepeatedConfirmationStartsOnlyOneViewModelTask() async throws {
        let container = try makeInMemoryTestContainer()
        let importer = ControlledBackupImporter()
        let viewModel = SettingsViewModel(backupImporter: importer)
        try viewModel.stageBackupImport(data: try validBackupData())

        viewModel.confirmBackupImport(context: container.mainContext)
        viewModel.confirmBackupImport(context: container.mainContext)
        await importer.waitUntilStarted()

        let callCount = await importer.callCount()
        XCTAssertEqual(callCount, 1)
        await importer.succeed()
        await waitUntil { !viewModel.isImportingBackup }
    }

    private func validBackupData() throws -> Data {
        let date = Date(timeIntervalSinceReferenceDate: 10)
        let bookID = UUID()
        let backup = KotobaBackupFile(
            appVersion: "test",
            schemaVersion: KotobaBackupService.schemaVersion,
            exportedAt: date,
            wordBooks: [
                BackupWordBook(
                    id: bookID,
                    name: "UI 测试",
                    bookDescription: "",
                    createdAt: date,
                    updatedAt: date,
                    isBuiltIn: false
                )
            ],
            vocabularyWords: [],
            learningProgress: [],
            reviewLogs: []
        )
        return try KotobaBackupService.encodeBackupSnapshot(backup)
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertTrue(condition())
    }
}

private enum ControlledBackupImporterError: Error, Sendable {
    case expected
}

private actor ControlledBackupImporter: KotobaBackupImporting {
    private var started = false
    private var calls = 0
    private var continuation: CheckedContinuation<KotobaBackupImportResult, Error>?

    func importBackup(
        from data: Data,
        strategy: KotobaBackupImportStrategy
    ) async throws -> KotobaBackupImportResult {
        calls += 1
        started = true
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }

    func callCount() -> Int {
        calls
    }

    func succeed() {
        continuation?.resume(returning: KotobaBackupImportResult(
            insertedWordBookCount: 1,
            insertedWordCount: 0,
            insertedProgressCount: 0,
            insertedReviewLogCount: 0,
            updatedCount: 0,
            skippedCount: 0
        ))
        continuation = nil
    }

    func fail() {
        continuation?.resume(throwing: ControlledBackupImporterError.expected)
        continuation = nil
    }
}
