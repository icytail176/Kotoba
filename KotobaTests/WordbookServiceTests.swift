//
//  WordBookServiceTests.swift
//  KotobaTests
//
//  Created by Codex on 2026/6/17.
//

import SwiftData
import XCTest
@testable import Kotoba

@MainActor
final class WordBookServiceTests: XCTestCase {
    private let service = WordBookService()

    func testCreateWordBookSavesAndCanBeFetchedFromANewContext() throws {
        let container = try makeInMemoryTestContainer()
        var draft = WordBookDraft()
        draft.name = "测试词书"
        draft.bookDescription = "用于创建验证"

        let created = try service.createWordBook(from: draft, in: container.mainContext)
        let reloadedContext = ModelContext(container)
        let books = try service.fetchWordBooks(in: reloadedContext)

        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books.first?.id, created.id)
        XCTAssertEqual(books.first?.name, "测试词书")
        XCTAssertFalse(books.first?.isBuiltIn ?? true)
    }

    func testCreateWordBookRejectsAnEmptyName() throws {
        let container = try makeInMemoryTestContainer()

        XCTAssertThrowsError(try service.createWordBook(from: WordBookDraft(), in: container.mainContext)) { error in
            XCTAssertEqual(error as? WordBookValidationError, .missingName)
        }
    }

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

    func testBuiltInWordBookCannotBeDeletedOrRenamed() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let builtInBook = WordBook(name: "JLPT N5", isBuiltIn: true)
        context.insert(builtInBook)
        try context.save()

        XCTAssertThrowsError(try service.deleteWordBook(builtInBook, in: context)) { error in
            XCTAssertEqual(error as? WordBookValidationError, .builtInWordBookCannotBeDeleted)
        }

        var draft = WordBookDraft(wordBook: builtInBook)
        draft.name = "用户重命名"
        XCTAssertThrowsError(try service.updateWordBook(builtInBook, from: draft, in: context)) { error in
            XCTAssertEqual(error as? WordBookValidationError, .builtInWordBookCannotBeModified)
        }
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

    func testRelearnOnlyResetsSelectedWordBookAndPreservesLearningHistory() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let selectedBook = WordBook(name: "需要重学")
        let otherBook = WordBook(name: "不应受影响")
        let selectedWord = makeWord(
            "確認",
            reading: "かくにん",
            wordBook: selectedBook,
            state: .review,
            reviewCount: 8
        )
        selectedWord.progress?.dueAt = now.addingTimeInterval(-60)
        selectedWord.progress?.intervalDays = 30
        selectedWord.progress?.lapseCount = 2
        selectedWord.progress?.lastReviewedAt = now.addingTimeInterval(-100)
        selectedWord.reviewLogs = [
            ReviewLog(
                reviewedAt: now.addingTimeInterval(-100),
                rating: .good,
                previousState: .review,
                nextState: .review,
                previousIntervalDays: 15,
                nextIntervalDays: 30,
                scheduledDueAt: now.addingTimeInterval(100),
                word: selectedWord
            )
        ]
        let otherWord = makeWord(
            "便利",
            reading: "べんり",
            wordBook: otherBook,
            state: .review,
            reviewCount: 4
        )
        otherWord.progress?.intervalDays = 12

        context.insert(selectedBook)
        context.insert(otherBook)
        context.insert(selectedWord)
        context.insert(otherWord)
        try context.save()

        let summary = service.relearnSummary(for: selectedBook, now: now)
        XCTAssertEqual(summary.totalWordCount, 1)
        XCTAssertEqual(summary.learnedWordCount, 1)
        XCTAssertEqual(summary.dueReviewCount, 1)

        try service.resetLearningProgress(for: selectedBook, in: context, now: now)

        let resetProgress = try XCTUnwrap(selectedWord.progress)
        XCTAssertEqual(resetProgress.state, .new)
        XCTAssertEqual(resetProgress.dueAt, now)
        XCTAssertEqual(resetProgress.intervalDays, 0)
        XCTAssertEqual(resetProgress.reviewCount, 0)
        XCTAssertEqual(resetProgress.lapseCount, 0)
        XCTAssertNil(resetProgress.lastReviewedAt)
        XCTAssertEqual(selectedWord.reviewLogs.count, 1)

        XCTAssertEqual(otherWord.progress?.state, .review)
        XCTAssertEqual(otherWord.progress?.intervalDays, 12)
        XCTAssertEqual(otherWord.progress?.reviewCount, 4)
    }

    func testSummariesAggregateCountsAcrossWordBooks() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSinceReferenceDate: 20_000)
        let firstBook = WordBook(name: "第一本")
        let secondBook = WordBook(name: "第二本")
        let newWord = makeWord("学生", reading: "がくせい", wordBook: firstBook, state: .new, reviewCount: 0)
        let learningWord = makeWord("食べる", reading: "たべる", wordBook: firstBook, state: .learning, reviewCount: 1)
        let relearningWord = makeWord("飲む", reading: "のむ", wordBook: firstBook, state: .relearning, reviewCount: 2)
        let reviewWord = makeWord("確認", reading: "かくにん", wordBook: firstBook, state: .review, reviewCount: 3)
        reviewWord.progress?.dueAt = now.addingTimeInterval(-60)
        let masteredWord = makeWord("覚える", reading: "おぼえる", wordBook: firstBook, state: .suspended, reviewCount: 4)
        let archivedWord = makeWord("古い", reading: "ふるい", wordBook: firstBook, state: .suspended, reviewCount: 1)
        archivedWord.isArchived = true
        let secondBookWord = makeWord("便利", reading: "べんり", wordBook: secondBook, state: .review, reviewCount: 2)
        secondBookWord.progress?.dueAt = now.addingTimeInterval(60)

        context.insert(firstBook)
        context.insert(secondBook)
        [newWord, learningWord, relearningWord, reviewWord, masteredWord, archivedWord, secondBookWord].forEach {
            context.insert($0)
        }
        try context.save()

        let summaries = try service.summaries(
            for: [firstBook, secondBook],
            in: context,
            selectedIDString: firstBook.id.uuidString,
            now: now
        )
        let firstSummary = try XCTUnwrap(summaries.first { $0.id == firstBook.id })
        let secondSummary = try XCTUnwrap(summaries.first { $0.id == secondBook.id })

        XCTAssertEqual(firstSummary.totalWordCount, 5)
        XCTAssertEqual(firstSummary.newWordCount, 1)
        XCTAssertEqual(firstSummary.learningWordCount, 2)
        XCTAssertEqual(firstSummary.reviewWordCount, 1)
        XCTAssertEqual(firstSummary.masteredWordCount, 1)
        XCTAssertEqual(firstSummary.dueReviewCount, 1)
        XCTAssertTrue(firstSummary.isSelected)
        XCTAssertEqual(secondSummary.totalWordCount, 1)
        XCTAssertEqual(secondSummary.dueReviewCount, 1)
    }

    func testFetchPreviewWordsScopesAndLimitsResults() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let firstBook = WordBook(name: "第一本")
        let secondBook = WordBook(name: "第二本")
        let words = [
            makeWord("学生", reading: "がくせい", wordBook: firstBook, state: .new, reviewCount: 0),
            makeWord("確認", reading: "かくにん", wordBook: firstBook, state: .new, reviewCount: 0),
            makeWord("先生", reading: "せんせい", wordBook: secondBook, state: .new, reviewCount: 0)
        ]
        words[1].isArchived = true

        context.insert(firstBook)
        context.insert(secondBook)
        words.forEach { context.insert($0) }
        try context.save()

        let previewWords = try service.fetchPreviewWords(
            in: context,
            wordBookID: firstBook.id,
            limit: 10
        )

        XCTAssertEqual(previewWords.map(\.id), [words[0].id])
    }

    func testManualCreateAndEditEnforceDuplicateIdentityWithinOneWordBook() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let bookA = WordBook(name: "A")
        let bookB = WordBook(name: "B")
        let first = makeWord("食べる", reading: "たべる", wordBook: bookA, state: .new, reviewCount: 0)
        let second = makeWord("飲む", reading: "のむ", wordBook: bookA, state: .new, reviewCount: 0)
        context.insert(bookA)
        context.insert(bookB)
        context.insert(first)
        context.insert(second)
        try context.save()
        let wordService = WordbookService()
        var duplicateDraft = WordEditorDraft()
        duplicateDraft.expression = "  食べる "
        duplicateDraft.reading = "たべる"
        duplicateDraft.meaningChinese = "吃"

        XCTAssertThrowsError(try wordService.createWord(from: duplicateDraft, wordBook: bookA, in: context)) { error in
            XCTAssertEqual(error as? WordbookValidationError, .duplicateWord)
        }
        XCTAssertNoThrow(try wordService.createWord(from: duplicateDraft, wordBook: bookB, in: context))

        var unchangedDraft = WordEditorDraft(word: first)
        unchangedDraft.meaningChinese = "吃东西"
        XCTAssertNoThrow(try wordService.updateWord(first, from: unchangedDraft, in: context))

        var collidingDraft = WordEditorDraft(word: first)
        collidingDraft.expression = "飲む"
        collidingDraft.reading = "のむ"
        XCTAssertThrowsError(try wordService.updateWord(first, from: collidingDraft, in: context)) { error in
            XCTAssertEqual(error as? WordbookValidationError, .duplicateWord)
        }
    }

    func testManualIdentityEditClearsLoanwordMetadataButOtherEditsPreserveIt() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let book = WordBook(name: "用户词书")
        let word = VocabularyWord(
            japanese: "コンピューター",
            kana: "コンピューター",
            chineseMeaning: "电脑",
            jlptLevel: "N5",
            loanwordSourceTerm: "computer",
            loanwordSourceLanguageCode: "eng",
            loanwordIsPartial: true,
            wordBook: book
        )
        word.progress = LearningProgress(state: .new, word: word)
        context.insert(book)
        context.insert(word)
        try context.save()
        let wordService = WordbookService()

        var meaningDraft = WordEditorDraft(word: word)
        meaningDraft.meaningChinese = "计算机"
        meaningDraft.exampleJapanese = "コンピューターを使う。"
        try wordService.updateWord(word, from: meaningDraft, in: context)
        XCTAssertEqual(word.loanwordSourceTerm, "computer")
        XCTAssertEqual(word.loanwordSourceLanguageCode, "eng")
        XCTAssertTrue(word.loanwordIsPartial)

        var identityDraft = WordEditorDraft(word: word)
        identityDraft.expression = "別の表記"
        try wordService.updateWord(word, from: identityDraft, in: context)
        XCTAssertNil(word.loanwordSourceTerm)
        XCTAssertNil(word.loanwordSourceLanguageCode)
        XCTAssertFalse(word.loanwordIsWasei)
        XCTAssertFalse(word.loanwordIsPartial)
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
