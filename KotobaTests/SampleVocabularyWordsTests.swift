//
//  SampleVocabularyWordsTests.swift
//  KotobaTests
//
//  Created by Codex on 2026/6/16.
//

import SwiftData
import XCTest

@MainActor
final class SampleVocabularyWordsTests: XCTestCase {
    func testSampleWordsContainTenWordsAcrossN5N4AndN3() {
        let words = SampleVocabularyWords.makeWords(referenceDate: Date(timeIntervalSinceReferenceDate: 0))
        let levels = Set(words.map(\.jlptLevel))

        XCTAssertEqual(words.count, 10)
        XCTAssertTrue(levels.contains("N5"))
        XCTAssertTrue(levels.contains("N4"))
        XCTAssertTrue(levels.contains("N3"))
        XCTAssertTrue(words.allSatisfy { $0.progress?.state == .new })
    }

    func testPreviewContainerSeedsSampleWordsOnce() throws {
        let container = PreviewModelContainer.make()
        let context = container.mainContext

        XCTAssertEqual(try context.fetch(FetchDescriptor<VocabularyWord>()).count, 10)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LearningProgress>()).count, 10)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WordBook>()).count, 1)
    }

    func testProductionStyleInMemoryContainerDoesNotSeedSampleWords() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext

        XCTAssertEqual(try context.fetch(FetchDescriptor<VocabularyWord>()).count, 0)
    }
}
