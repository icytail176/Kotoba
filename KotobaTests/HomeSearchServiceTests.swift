//
//  HomeSearchServiceTests.swift
//  KotobaTests
//
//  Created by Codex on 2026/6/17.
//

import SwiftData
import XCTest

@MainActor
final class HomeSearchServiceTests: XCTestCase {
    func testSearchCanBeScopedToCurrentWordBook() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let currentBook = WordBook(name: "当前")
        let otherBook = WordBook(name: "其他")
        let currentWord = makeWord("先生", reading: "せんせい", meaning: "老师", wordBook: currentBook)
        let otherWord = makeWord("先生", reading: "せんせい", meaning: "老师", wordBook: otherBook)

        context.insert(currentBook)
        context.insert(otherBook)
        context.insert(currentWord)
        context.insert(otherWord)
        try context.save()

        let suggestions = try HomeSearchService().suggestions(
            in: context,
            query: "先生",
            scope: .currentWordBook,
            currentWordBookID: currentBook.id
        )

        XCTAssertEqual(suggestions.map(\.wordID), [currentWord.id])
    }

    func testSearchRanksExpressionExactBeforeMeaningMatch() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let book = WordBook(name: "词书")
        let exact = makeWord("学校", reading: "がっこう", meaning: "学校", wordBook: book)
        let meaningOnly = makeWord("校庭", reading: "こうてい", meaning: "学校操场", wordBook: book)

        context.insert(book)
        context.insert(meaningOnly)
        context.insert(exact)
        try context.save()

        let suggestions = try HomeSearchService().suggestions(
            in: context,
            query: "学校",
            scope: .allWordBooks,
            currentWordBookID: nil
        )

        XCTAssertEqual(suggestions.first?.wordID, exact.id)
    }

    private func makeWord(
        _ expression: String,
        reading: String,
        meaning: String,
        wordBook: WordBook
    ) -> VocabularyWord {
        VocabularyWord(
            japanese: expression,
            kana: reading,
            chineseMeaning: meaning,
            jlptLevel: "N5",
            wordBook: wordBook
        )
    }
}
