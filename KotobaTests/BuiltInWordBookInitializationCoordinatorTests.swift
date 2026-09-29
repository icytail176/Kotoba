//
//  BuiltInWordBookInitializationCoordinatorTests.swift
//  KotobaTests
//

import Foundation
import SwiftData
import XCTest
@testable import Kotoba

@MainActor
final class BuiltInWordBookInitializationCoordinatorTests: XCTestCase {
    func testTenConcurrentCallersShareOneInitialization() async throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let defaults = try makeDefaults()
        let definition = BuiltInWordBookDefinition(
            level: "N5",
            displayName: "JLPT N5",
            fileName: "test.csv",
            expectedWordCount: 1
        )
        var resourceReadCount = 0
        let coordinator = BuiltInWordBookInitializationCoordinator {
            BuiltInWordBookService(
                definitions: [definition],
                dataProvider: { _ in
                    resourceReadCount += 1
                    return Data(
                        "expression,reading,meaningChinese,partOfSpeech,exampleJapanese,exampleChinese,jlptLevel,tags\n学生,がくせい,学生,名词,,,N5,学校\n".utf8
                    )
                },
                userDefaults: defaults
            )
        }
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        async let result1 = coordinator.loadIfNeeded(in: context, now: now)
        async let result2 = coordinator.loadIfNeeded(in: context, now: now)
        async let result3 = coordinator.loadIfNeeded(in: context, now: now)
        async let result4 = coordinator.loadIfNeeded(in: context, now: now)
        async let result5 = coordinator.loadIfNeeded(in: context, now: now)
        async let result6 = coordinator.loadIfNeeded(in: context, now: now)
        async let result7 = coordinator.loadIfNeeded(in: context, now: now)
        async let result8 = coordinator.loadIfNeeded(in: context, now: now)
        async let result9 = coordinator.loadIfNeeded(in: context, now: now)
        async let result10 = coordinator.loadIfNeeded(in: context, now: now)
        let results = try await [
            result1, result2, result3, result4, result5,
            result6, result7, result8, result9, result10
        ]

        XCTAssertEqual(resourceReadCount, 1)
        XCTAssertTrue(results.dropFirst().allSatisfy { $0 == results[0] })
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WordBook>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<VocabularyWord>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LearningProgress>()), 1)
        XCTAssertEqual(
            defaults.integer(forKey: AppSettings.builtInWordBookSeedVersionKey),
            BuiltInWordBookService.builtInVocabularyVersion
        )
    }

    func testFailedInitializationCanRetrySuccessfully() async throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let defaults = try makeDefaults()
        let definition = BuiltInWordBookDefinition(
            level: "N5",
            displayName: "JLPT N5",
            fileName: "test.csv",
            expectedWordCount: 1
        )
        var shouldFail = true
        let coordinator = BuiltInWordBookInitializationCoordinator {
            BuiltInWordBookService(
                definitions: [definition],
                dataProvider: { _ in
                    if shouldFail {
                        throw BuiltInWordBookError.resourceNotFound("test.csv")
                    }
                    return Data(
                        "expression,reading,meaningChinese,partOfSpeech,exampleJapanese,exampleChinese,jlptLevel,tags\n学生,がくせい,学生,名词,,,N5,学校\n".utf8
                    )
                },
                userDefaults: defaults
            )
        }

        do {
            _ = try await coordinator.loadIfNeeded(in: context)
            XCTFail("Expected the injected resource failure")
        } catch {
            XCTAssertEqual(error as? BuiltInWordBookError, .resourceNotFound("test.csv"))
        }
        XCTAssertEqual(defaults.integer(forKey: AppSettings.builtInWordBookSeedVersionKey), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<VocabularyWord>()), 0)

        shouldFail = false
        _ = try await coordinator.loadIfNeeded(in: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<VocabularyWord>()), 1)
        XCTAssertEqual(
            defaults.integer(forKey: AppSettings.builtInWordBookSeedVersionKey),
            BuiltInWordBookService.builtInVocabularyVersion
        )
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "BuiltInWordBookInitializationCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
