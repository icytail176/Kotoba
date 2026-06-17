//
//  HomeDashboardServiceTests.swift
//  KotobaTests
//
//  Created by Codex on 2026/6/17.
//

import SwiftData
import XCTest

@MainActor
final class HomeDashboardServiceTests: XCTestCase {
    func testRandomExampleUsesOnlySelectedWordBookAndRequiresBothExamples() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let selectedBook = WordBook(name: "当前词书")
        let otherBook = WordBook(name: "其他词书")
        let selectedWord = makeWord(
            "努力",
            exampleJapanese: "毎日の努力が大切です。",
            exampleChinese: "每天的努力很重要。",
            wordBook: selectedBook
        )
        let incompleteWord = makeWord(
            "水",
            exampleJapanese: "水を飲みます。",
            exampleChinese: "",
            wordBook: selectedBook
        )
        let otherWord = makeWord(
            "影響",
            exampleJapanese: "影響があります。",
            exampleChinese: "有影响。",
            wordBook: otherBook
        )

        context.insert(selectedBook)
        context.insert(otherBook)
        context.insert(selectedWord)
        context.insert(incompleteWord)
        context.insert(otherWord)
        try context.save()

        let service = HomeDashboardService()
        let result = try service.makeSnapshot(
            in: context,
            selectedIDString: selectedBook.id.uuidString,
            dailyNewWordLimit: 20
        )

        XCTAssertEqual(result.snapshot.example?.wordID, selectedWord.id)
        XCTAssertEqual(result.snapshot.example?.expression, "努力")
    }

    func testHighlightingMarksAllTargetMatchesAndSurvivesMissingTarget() {
        let service = ExampleHighlightingService()

        let segments = service.segments(in: "努力と努力が必要です。", target: "努力")
        XCTAssertEqual(segments.filter(\.isHighlighted).map(\.text), ["努力", "努力"])
        XCTAssertEqual(segments.map(\.text).joined(), "努力と努力が必要です。")

        let missing = service.segments(in: "毎日続けます。", target: "努力")
        XCTAssertEqual(missing, [HighlightedTextSegment(text: "毎日続けます。", isHighlighted: false)])
    }

    private func makeWord(
        _ expression: String,
        exampleJapanese: String,
        exampleChinese: String,
        wordBook: WordBook
    ) -> VocabularyWord {
        let word = VocabularyWord(
            japanese: expression,
            kana: expression,
            chineseMeaning: expression,
            jlptLevel: "N5",
            exampleJapanese: exampleJapanese,
            exampleChinese: exampleChinese,
            wordBook: wordBook
        )
        word.progress = LearningProgress(state: .new, word: word)
        return word
    }
}
