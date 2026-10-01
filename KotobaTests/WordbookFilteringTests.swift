//
//  WordbookFilteringTests.swift
//  KotobaTests
//
//  Created by Codex on 2026/6/17.
//

import XCTest
import SwiftData
@testable import Kotoba

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

    func testFetchWordsForWordBookUsesPersistentScope() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let currentBook = WordBook(name: "当前")
        let otherBook = WordBook(name: "其他")
        let currentWord = makeWord("確認", wordBook: currentBook)
        let otherWord = makeWord("学生", wordBook: otherBook)
        context.insert(currentBook)
        context.insert(otherBook)
        context.insert(currentWord)
        context.insert(otherWord)
        try context.save()

        let words = try service.fetchWords(in: context, wordBookID: currentBook.id)

        XCTAssertEqual(words.map(\.id), [currentWord.id])
    }

    func testOptionSetQueryReadsMetadataWithoutRequiringLearningRelationships() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let wordBook = WordBook(name: "筛选选项")
        let word = makeWord("確認", partOfSpeech: "名词/サ变动词", wordBook: wordBook)
        word.tags = ["高频", "工作"]
        context.insert(wordBook)
        context.insert(word)
        try context.save()

        let freshContext = ModelContext(container)
        let optionSets = try service.makeOptionSets(
            in: freshContext,
            scopedWordBookID: wordBook.id,
            wordBooks: [wordBook]
        )

        XCTAssertEqual(optionSets.jlptLevels, ["N5"])
        XCTAssertEqual(Set(optionSets.partsOfSpeech), Set(["サ变动词", "名词"]))
        XCTAssertEqual(Set(optionSets.tags), Set(["工作", "高频"]))
    }

    func testFilterResultLimitsVisibleRowsButKeepsMatchingCount() {
        let firstBook = WordBook(name: "当前")
        let words = [
            makeWord("確認", meaning: "确认", wordBook: firstBook),
            makeWord("確定", meaning: "确定", wordBook: firstBook),
            makeWord("確認する", meaning: "进行确认", wordBook: firstBook)
        ]
        var filters = WordbookFilters()
        filters.searchText = "确"

        let result = service.filterResult(
            words,
            using: filters,
            currentWordBookID: firstBook.id,
            visibleLimit: 2,
            selectedWordID: words[2].id
        )

        XCTAssertEqual(result.matchingCount, 3)
        XCTAssertEqual(result.visibleWords.map(\.id), words.prefix(2).map(\.id))
        XCTAssertTrue(result.selectedWordMatches)
    }

    func testPersistentPaginationReturnsAtMostFiftyRowsPerPage() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let wordBook = WordBook(name: "分页测试")
        context.insert(wordBook)
        for index in 0..<120 {
            context.insert(makeWord(String(format: "词%03d", index), wordBook: wordBook))
        }
        try context.save()

        let firstPage = try service.fetchWordPage(
            in: context,
            scopedWordBookID: wordBook.id,
            filters: WordbookFilters(),
            offset: 0,
            limit: WordbookViewModel.pageSize
        )
        let secondPage = try service.fetchWordPage(
            in: context,
            scopedWordBookID: wordBook.id,
            filters: WordbookFilters(),
            offset: 50,
            limit: WordbookViewModel.pageSize
        )
        let thirdPage = try service.fetchWordPage(
            in: context,
            scopedWordBookID: wordBook.id,
            filters: WordbookFilters(),
            offset: 100,
            limit: WordbookViewModel.pageSize
        )

        XCTAssertEqual(firstPage.rows.count, 50)
        XCTAssertEqual(secondPage.rows.count, 50)
        XCTAssertEqual(thirdPage.rows.count, 20)
        XCTAssertEqual(firstPage.matchingCount, 120)
        XCTAssertTrue(firstPage.isMatchingCountExact)
        XCTAssertTrue(firstPage.hasNextPage)
        XCTAssertTrue(secondPage.hasNextPage)
        XCTAssertFalse(thirdPage.hasNextPage)
        XCTAssertEqual(
            Set(firstPage.rows.map(\.id) + secondPage.rows.map(\.id) + thirdPage.rows.map(\.id)).count,
            120
        )
    }

    func testLargeWordbookStillMaterializesOnlyOnePage() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let wordBook = WordBook(name: "大词库")
        context.insert(wordBook)
        for index in 0..<2_000 {
            context.insert(makeWord(String(format: "大词%04d", index), wordBook: wordBook))
        }
        try context.save()

        let page = try service.fetchWordPage(
            in: context,
            scopedWordBookID: wordBook.id,
            filters: WordbookFilters(),
            offset: 0,
            limit: WordbookViewModel.pageSize
        )

        XCTAssertEqual(page.rows.count, 50)
        XCTAssertEqual(page.matchingCount, 2_000)
        XCTAssertTrue(page.hasNextPage)
    }

    func testSearchFiltersCompleteCollectionBeforeReturningRequestedPage() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let wordBook = WordBook(name: "搜索分页")
        context.insert(wordBook)
        for index in 0..<120 {
            let meaning = index.isMultiple(of: 2) ? "目标" : "其他"
            context.insert(
                makeWord(String(format: "词%03d", index), meaning: meaning, wordBook: wordBook)
            )
        }
        try context.save()

        var filters = WordbookFilters()
        filters.searchText = "目标"
        let firstPage = try service.fetchWordPage(
            in: context,
            scopedWordBookID: wordBook.id,
            filters: filters,
            offset: 0,
            limit: WordbookViewModel.pageSize
        )
        let secondPage = try service.fetchWordPage(
            in: context,
            scopedWordBookID: wordBook.id,
            filters: filters,
            offset: 50,
            limit: WordbookViewModel.pageSize
        )

        XCTAssertEqual(firstPage.rows.count, 50)
        XCTAssertTrue(firstPage.rows.allSatisfy { $0.meaningChinese == "目标" })
        XCTAssertTrue(firstPage.hasNextPage)
        XCTAssertEqual(secondPage.rows.count, 10)
        XCTAssertTrue(secondPage.rows.allSatisfy { $0.meaningChinese == "目标" })
        XCTAssertFalse(secondPage.hasNextPage)
        XCTAssertTrue(secondPage.isMatchingCountExact)
        XCTAssertEqual(secondPage.matchingCount, 60)
    }

    func testViewModelMovesBetweenFiftyRowPagesWithoutAccumulatingRows() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let wordBook = WordBook(name: "视图分页")
        context.insert(wordBook)
        for index in 0..<105 {
            context.insert(makeWord(String(format: "词%03d", index), wordBook: wordBook))
        }
        try context.save()

        let viewModel = WordbookViewModel()
        viewModel.loadWords(context: context, selectedWordBookID: wordBook.id.uuidString)
        XCTAssertEqual(viewModel.currentPage, 1)
        XCTAssertEqual(viewModel.filteredWords.count, 50)
        XCTAssertTrue(viewModel.hasNextPage)
        XCTAssertFalse(viewModel.hasPreviousPage)

        viewModel.goToNextPage(context: context)
        XCTAssertEqual(viewModel.currentPage, 2)
        XCTAssertEqual(viewModel.filteredWords.count, 50)
        XCTAssertTrue(viewModel.hasNextPage)
        XCTAssertTrue(viewModel.hasPreviousPage)

        viewModel.goToNextPage(context: context)
        XCTAssertEqual(viewModel.currentPage, 3)
        XCTAssertEqual(viewModel.filteredWords.count, 5)
        XCTAssertFalse(viewModel.hasNextPage)

        viewModel.goToPreviousPage(context: context)
        XCTAssertEqual(viewModel.currentPage, 2)
        XCTAssertEqual(viewModel.filteredWords.count, 50)

        var updatedFilters = viewModel.filters
        updatedFilters.searchText = "词001"
        viewModel.filters = updatedFilters
        XCTAssertEqual(viewModel.currentPage, 1)
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
