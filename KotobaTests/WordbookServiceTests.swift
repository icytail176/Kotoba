//
//  WordBookServiceTests.swift
//  KotobaTests
//
//  Created by Codex on 2026/6/17.
//

import SwiftData
import XCTest

@MainActor
final class WordBookServiceTests: XCTestCase {
    private let service = WordBookService()

    func testSameWordCanExistInDifferentWordBooksWithIndependentProgress() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let bookA = WordBook(name: "N5")
        let bookB = WordBook(name: "校园日语")
        let wordA = makeWord("先生", reading: "せんせい", wordBook: bookA, state: .review, reviewCount: 3)
        let wordB = makeWord("先生", reading: "せんせい", wordBook: bookB, state: .new, reviewCount: 0)

        context.insert(bookA)
        context.insert(bookB)
        context.insert(wordA)
        context.insert(wordB)
        try context.save()

        let books = try service.fetchWordBooks(in: context)

        XCTAssertEqual(books.count, 2)
        XCTAssertEqual(wordA.wordBook?.id, bookA.id)
        XCTAssertEqual(wordB.wordBook?.id, bookB.id)
        XCTAssertEqual(wordA.progress?.state, .review)
        XCTAssertEqual(wordA.progress?.reviewCount, 3)
        XCTAssertEqual(wordB.progress?.state, .new)
        XCTAssertEqual(wordB.progress?.reviewCount, 0)
    }

    func testLegacyWordsAreMigratedOnceWithoutChangingProgressOrLogs() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let dueAt = Date(timeIntervalSinceReferenceDate: 2_000)
        let word = makeWord("確認", reading: "かくにん", wordBook: nil, state: .review, reviewCount: 7)
        word.isFavorite = true
        word.progress?.dueAt = dueAt
        word.progress?.intervalDays = 12
        word.reviewLogs = [
            ReviewLog(
                reviewedAt: now,
                rating: .good,
                previousState: .learning,
                nextState: .review,
                previousIntervalDays: 1,
                nextIntervalDays: 12,
                scheduledDueAt: dueAt,
                word: word
            )
        ]

        context.insert(word)
        try context.save()

        try service.migrateLegacyWordsIfNeeded(in: context, now: now)
        try service.migrateLegacyWordsIfNeeded(in: context, now: now.addingTimeInterval(60))

        let books = try context.fetch(FetchDescriptor<WordBook>())
        let words = try context.fetch(FetchDescriptor<VocabularyWord>())
        let logs = try context.fetch(FetchDescriptor<ReviewLog>())

        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books.first?.name, WordBookService.migratedDefaultBookName)
        XCTAssertEqual(words.first?.id, word.id)
        XCTAssertEqual(words.first?.wordBook?.id, books.first?.id)
        XCTAssertEqual(words.first?.progress?.reviewCount, 7)
        XCTAssertEqual(words.first?.progress?.dueAt, dueAt)
        XCTAssertEqual(words.first?.progress?.intervalDays, 12)
        XCTAssertEqual(words.first?.isFavorite, true)
        XCTAssertEqual(logs.count, 1)
    }

    func testDeletingWordBookDeletesWordsProgressAndLogs() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let book = WordBook(name: "删除测试")
        let word = makeWord("説明", reading: "せつめい", wordBook: book, state: .review, reviewCount: 1)
        word.reviewLogs = [
            ReviewLog(
                reviewedAt: Date(),
                rating: .good,
                previousState: .learning,
                nextState: .review,
                previousIntervalDays: 1,
                nextIntervalDays: 2,
                scheduledDueAt: Date(),
                word: word
            )
        ]

        context.insert(book)
        context.insert(word)
        try context.save()

        try service.deleteWordBook(book, in: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<WordBook>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<VocabularyWord>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LearningProgress>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ReviewLog>()).count, 0)
    }

    func testInvalidSelectedWordBookIDFallsBackToFirstBook() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let firstBook = WordBook(name: "第一本", createdAt: Date(timeIntervalSinceReferenceDate: 1))
        let secondBook = WordBook(name: "第二本", createdAt: Date(timeIntervalSinceReferenceDate: 2))

        context.insert(firstBook)
        context.insert(secondBook)
        try context.save()

        let selected = try service.resolveSelectedWordBook(
            in: context,
            selectedIDString: UUID().uuidString
        )

        XCTAssertEqual(selected?.id, firstBook.id)
    }

    private func makeWord(
        _ expression: String,
        reading: String,
        wordBook: WordBook?,
        state: LearningState,
        reviewCount: Int
    ) -> VocabularyWord {
        let word = VocabularyWord(
            japanese: expression,
            kana: reading,
            chineseMeaning: expression,
            jlptLevel: "N5",
            wordBook: wordBook
        )
        word.progress = LearningProgress(
            state: state,
            reviewCount: reviewCount,
            word: word
        )
        return word
    }
}
