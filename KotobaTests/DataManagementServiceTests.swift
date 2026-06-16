//
//  DataManagementServiceTests.swift
//  KotobaTests
//
//  Created by Codex on 2026/6/16.
//

import SwiftData
import XCTest

@MainActor
final class DataManagementServiceTests: XCTestCase {
    func testClearAllDataDeletesWordsProgressAndReviewLogs() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let word = VocabularyWord(
            japanese: "確認",
            kana: "かくにん",
            chineseMeaning: "确认",
            jlptLevel: "N3"
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

        context.insert(word)
        try context.save()

        try DataManagementService().clearAllData(in: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<VocabularyWord>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LearningProgress>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ReviewLog>()).count, 0)
    }
}
