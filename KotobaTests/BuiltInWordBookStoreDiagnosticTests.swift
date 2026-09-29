//
//  BuiltInWordBookStoreDiagnosticTests.swift
//  KotobaTests
//

import Foundation
import SwiftData
import XCTest
@testable import Kotoba

/// Debug-only entry point for validating repair against a copied store family.
/// It is inert during the normal suite unless KOTOBA_DIAGNOSTIC_STORE_URL is set.
@MainActor
final class BuiltInWordBookStoreDiagnosticTests: XCTestCase {
    private struct UserDataSignature: Equatable {
        let wordID: UUID
        let isFavorite: Bool
        let progressID: UUID?
        let state: LearningState?
        let dueAt: Date?
        let intervalDays: Int?
        let reviewCount: Int?
        let lapseCount: Int?
        let lastReviewedAt: Date?
        let reviewLogIDs: [UUID]
    }

    func testRepairCopiedStoreWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["KOTOBA_DIAGNOSTIC_STORE_URL"],
              !path.isEmpty else {
            return
        }

        let storeURL = URL(fileURLWithPath: path)
        let container = try KotobaStore.makeContainer(at: storeURL)
        let context = container.mainContext
        let defaultsSuite = "BuiltInWordBookStoreDiagnosticTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        defaults.removePersistentDomain(forName: defaultsSuite)
        defaults.set(5, forKey: AppSettings.builtInWordBookSeedVersionKey)

        let beforeWords = try context.fetch(FetchDescriptor<VocabularyWord>())
        let beforeSignatures = Dictionary(
            uniqueKeysWithValues: beforeWords
                .filter(hasUserData)
                .map { ($0.id, signature(for: $0)) }
        )
        let beforeReviewLogCount = try context.fetchCount(FetchDescriptor<ReviewLog>())
        let beforeFavoriteCount = beforeWords.filter(\.isFavorite).count
        printHealth("before", context: context)

        let service = BuiltInWordBookService(
            dataProvider: { definition in
                try Data(contentsOf: self.resourceURL(definition.fileName))
            },
            etymologyDataProvider: {
                try Data(contentsOf: self.resourceURL("builtin_loanword_etymology.csv"))
            },
            userDefaults: defaults
        )
        _ = try service.loadIfNeeded(in: context)
        _ = try service.loadIfNeeded(in: context)
        _ = try service.loadIfNeeded(in: context)

        let afterWords = try context.fetch(FetchDescriptor<VocabularyWord>())
        let afterByID = Dictionary(uniqueKeysWithValues: afterWords.map { ($0.id, $0) })
        for (wordID, beforeSignature) in beforeSignatures {
            let afterWord = try XCTUnwrap(afterByID[wordID], "User-data word \(wordID) was removed")
            XCTAssertEqual(signature(for: afterWord), beforeSignature, "User data changed for \(wordID)")
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReviewLog>()), beforeReviewLogCount)
        XCTAssertEqual(afterWords.filter(\.isFavorite).count, beforeFavoriteCount)
        XCTAssertEqual(defaults.integer(forKey: AppSettings.builtInWordBookSeedVersionKey), 6)

        let n5Book = try XCTUnwrap(
            try context.fetch(FetchDescriptor<WordBook>()).first { $0.name == "JLPT N5" && $0.isBuiltIn }
        )
        let home = try HomeDashboardService().makeSnapshot(
            in: context,
            selectedIDString: n5Book.id.uuidString
        ).snapshot
        XCTAssertEqual(home.totalWordCount, 802)
        XCTAssertEqual(afterWords.filter { !$0.isArchived && $0.wordBook?.isBuiltIn == true }.count, 10_609)
        printHealth("after", context: context)
    }

    private func hasUserData(_ word: VocabularyWord) -> Bool {
        guard let progress = word.progress else { return true }
        return word.isFavorite
            || !word.reviewLogs.isEmpty
            || progress.state != .new
            || progress.intervalDays != 0
            || progress.reviewCount != 0
            || progress.lapseCount != 0
            || progress.lastReviewedAt != nil
    }

    private func signature(for word: VocabularyWord) -> UserDataSignature {
        UserDataSignature(
            wordID: word.id,
            isFavorite: word.isFavorite,
            progressID: word.progress?.id,
            state: word.progress?.state,
            dueAt: word.progress?.dueAt,
            intervalDays: word.progress?.intervalDays,
            reviewCount: word.progress?.reviewCount,
            lapseCount: word.progress?.lapseCount,
            lastReviewedAt: word.progress?.lastReviewedAt,
            reviewLogIDs: word.reviewLogs.map(\.id).sorted { $0.uuidString < $1.uuidString }
        )
    }

    private func printHealth(_ label: String, context: ModelContext) {
        do {
            let books = try context.fetch(FetchDescriptor<WordBook>())
            let words = try context.fetch(FetchDescriptor<VocabularyWord>())
            let progressCount = try context.fetchCount(FetchDescriptor<LearningProgress>())
            let logCount = try context.fetchCount(FetchDescriptor<ReviewLog>())
            print(
                "[StoreDiagnostic] \(label)",
                "books=\(books.count)",
                "words=\(words.count)",
                "progress=\(progressCount)",
                "reviewLogs=\(logCount)",
                "favorites=\(words.filter(\.isFavorite).count)"
            )
            for definition in BuiltInWordBookDefinition.all {
                guard let book = books.first(where: { $0.isBuiltIn && $0.name == definition.displayName }) else {
                    print("[StoreDiagnostic] \(label) \(definition.level) missing")
                    continue
                }
                let bookWords = words.filter { $0.wordBook?.id == book.id }
                print(
                    "[StoreDiagnostic] \(label) \(definition.level)",
                    "expected=\(definition.expectedWordCount ?? 0)",
                    "active=\(bookWords.filter { !$0.isArchived }.count)",
                    "archived=\(bookWords.filter(\.isArchived).count)",
                    "physical=\(bookWords.count)"
                )
            }
        } catch {
            XCTFail("Store health report failed: \(error)")
        }
    }

    private func resourceURL(_ fileName: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Kotoba/Resources")
            .appendingPathComponent(fileName)
    }
}
