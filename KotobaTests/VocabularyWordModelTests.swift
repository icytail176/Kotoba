//
//  VocabularyWordModelTests.swift
//  KotobaTests
//
//  Created by Codex on 2026/6/16.
//

import SwiftData
import XCTest
@testable import Kotoba

@MainActor
final class VocabularyWordModelTests: XCTestCase {
    func testVocabularyWordStoresOneLearningProgress() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext

        let word = VocabularyWord(
            japanese: "学生",
            kana: "がくせい",
            chineseMeaning: "学生",
            partOfSpeech: "名词",
            jlptLevel: "N5"
        )
        let progress = LearningProgress(state: .new, word: word)
        word.progress = progress

        context.insert(word)
        try context.save()

        let words = try context.fetch(FetchDescriptor<VocabularyWord>())
        XCTAssertEqual(words.count, 1)
        XCTAssertEqual(words.first?.progress?.state, .new)
        XCTAssertEqual(words.first?.progress?.word?.japanese, "学生")
    }

    func testVocabularyWordStoresManyReviewLogs() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSinceReferenceDate: 0)

        let word = VocabularyWord(
            japanese: "確認",
            kana: "かくにん",
            chineseMeaning: "确认",
            partOfSpeech: "名词/サ变动词",
            jlptLevel: "N3"
        )
        word.reviewLogs = [
            ReviewLog(
                reviewedAt: now,
                rating: .good,
                previousState: .new,
                nextState: .review,
                previousIntervalDays: 0,
                nextIntervalDays: 2,
                scheduledDueAt: now.addingTimeInterval(2 * 24 * 60 * 60),
                word: word
            ),
            ReviewLog(
                reviewedAt: now.addingTimeInterval(60),
                rating: .hard,
                previousState: .review,
                nextState: .review,
                previousIntervalDays: 2,
                nextIntervalDays: 3,
                scheduledDueAt: now.addingTimeInterval(3 * 24 * 60 * 60),
                word: word
            )
        ]

        context.insert(word)
        try context.save()

        let words = try context.fetch(FetchDescriptor<VocabularyWord>())
        XCTAssertEqual(words.first?.reviewLogs.count, 2)
        XCTAssertEqual(words.first?.reviewLogs.map(\.rating).sorted { $0.rawValue < $1.rawValue }, [.good, .hard])
    }

    func testDeletingWordCascadesProgressAndReviewLogs() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSinceReferenceDate: 0)

        let word = VocabularyWord(
            japanese: "便利",
            kana: "べんり",
            chineseMeaning: "方便",
            partOfSpeech: "形容动词",
            jlptLevel: "N4"
        )
        word.progress = LearningProgress(state: .review, intervalDays: 4, word: word)
        word.reviewLogs = [
            ReviewLog(
                reviewedAt: now,
                rating: .easy,
                previousState: .new,
                nextState: .review,
                previousIntervalDays: 0,
                nextIntervalDays: 4,
                scheduledDueAt: now.addingTimeInterval(4 * 24 * 60 * 60),
                word: word
            )
        ]

        context.insert(word)
        try context.save()
        context.delete(word)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<VocabularyWord>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LearningProgress>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ReviewLog>()).count, 0)
    }
}
