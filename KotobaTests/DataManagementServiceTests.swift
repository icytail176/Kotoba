//
//  DataManagementServiceTests.swift
//  KotobaTests
//
//  Created by Codex on 2026/6/16.
//

import SwiftData
import XCTest
@testable import Kotoba

@MainActor
final class DataManagementServiceTests: XCTestCase {
    func testClearAllDataDeletesWordsProgressAndReviewLogs() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let wordBook = WordBook(name: "测试词书")
        let word = VocabularyWord(
            japanese: "確認",
            kana: "かくにん",
            chineseMeaning: "确认",
            jlptLevel: "N3",
            wordBook: wordBook
        )
        word.progress = LearningProgress(state: .review, dueAt: now, word: word)
        word.reviewLogs = [
            ReviewLog(
                reviewedAt: now,
                rating: .good,
                previousState: .new,
                nextState: .review,
                previousIntervalDays: 0,
                nextIntervalDays: 2,
                scheduledDueAt: now,
                word: word
            )
        ]

        context.insert(wordBook)
        context.insert(word)
        try context.save()

        try DataManagementService().clearAllData(in: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<WordBook>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<VocabularyWord>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LearningProgress>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ReviewLog>()).count, 0)
    }

    func testClearAllDataDeletesOrphanProgressAndReviewLogs() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let orphanProgress = LearningProgress(state: .review, dueAt: now)
        let orphanLog = ReviewLog(
            reviewedAt: now,
            rating: .again,
            previousState: .review,
            nextState: .relearning,
            previousIntervalDays: 12,
            nextIntervalDays: 0,
            scheduledDueAt: now.addingTimeInterval(600)
        )

        context.insert(orphanProgress)
        context.insert(orphanLog)
        try context.save()

        try DataManagementService().clearAllData(in: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<VocabularyWord>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LearningProgress>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ReviewLog>()).count, 0)
    }
}
