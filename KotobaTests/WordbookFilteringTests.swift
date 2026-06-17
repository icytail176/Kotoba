//
//  WordbookFilteringTests.swift
//  KotobaTests
//
//  Created by Codex on 2026/6/17.
//

import XCTest

@MainActor
final class WordbookFilteringTests: XCTestCase {
    private let service = WordbookService()

    func testPartOfSpeechTokensAreNormalizedAndMatchedExactly() throws {
        let tokenizer = PartOfSpeechTokenizer()

        XCTAssertEqual(
            tokenizer.normalized(" 名词 / サ变动词 / 名词 / "),
            "名词/サ变动词"
        )

        let verb = makeWord("食べる", partOfSpeech: "动词")
        let suruVerb = makeWord("確認", partOfSpeech: "名词/サ变动词")
        let noun = makeWord("学生", partOfSpeech: "名词")

        var filters = WordbookFilters(wordBookID: WordbookFilterValue.all.rawValue)
        filters.partOfSpeech = "动词"

        XCTAssertEqual(
            service.filter([verb, suruVerb, noun], using: filters, currentWordBookID: nil).map(\.japanese),
            ["食べる"]
        )
    }

    func testWordBookFilterUsesAndLogicWithTextSearch() {
        let currentBook = WordBook(name: "当前")
        let otherBook = WordBook(name: "其他")
        let currentWord = makeWord("確認", meaning: "确认", wordBook: currentBook)
        let otherWord = makeWord("確認", meaning: "确认", wordBook: otherBook)
        let distractor = makeWord("学生", meaning: "学生", wordBook: currentBook)

        var filters = WordbookFilters()
        filters.searchText = "确认"

        XCTAssertEqual(
            service.filter(
                [currentWord, otherWord, distractor],
                using: filters,
                currentWordBookID: currentBook.id
            ).map(\.wordBook?.id),
            [currentBook.id]
        )
    }

    private func makeWord(
        _ expression: String,
        meaning: String? = nil,
        partOfSpeech: String = "名词",
        wordBook: WordBook? = nil
    ) -> VocabularyWord {
        VocabularyWord(
            japanese: expression,
            kana: expression,
            chineseMeaning: meaning ?? expression,
            partOfSpeech: partOfSpeech,
            jlptLevel: "N5",
            wordBook: wordBook
        )
    }
}
