//
//  StudyQueueServiceTests.swift
//  KotobaTests
//
//  Created by Codex on 2026/6/16.
//

import SwiftData
import XCTest

@MainActor
final class StudyQueueServiceTests: XCTestCase {
    private var calendar: Calendar!
    private var service: StudyQueueService!

    override func setUp() {
        super.setUp()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        self.calendar = calendar
        service = StudyQueueService(calendar: calendar)
    }

    override func tearDown() {
        service = nil
        calendar = nil
        super.tearDown()
    }

    func testDueReviewsAreSortedBeforeNewWords() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        let olderDue = makeWord("確認", state: .review, dueAt: addingHours(-3, to: now), createdAt: addingDays(-5, to: now))
        let newerDue = makeWord("便利", state: .review, dueAt: addingHours(-1, to: now), createdAt: addingDays(-4, to: now))
        let newWord = makeWord("学生", state: .new, dueAt: now, createdAt: addingDays(-3, to: now))

        [newWord, newerDue, olderDue].forEach(context.insert)
        try context.save()

        let session = try service.buildSession(in: context, now: now, dailyNewWordLimit: 20)

        XCTAssertEqual(session.status, .ready)
        XCTAssertEqual(session.items.map { $0.word.japanese }, ["確認", "便利", "学生"])
        XCTAssertEqual(session.items.map(\.kind), [.dueReview, .dueReview, .newWord])
    }

    func testDefaultDailyNewWordLimitIsTwenty() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)

        for index in 0..<25 {
            context.insert(makeWord("新词\(index)", state: .new, dueAt: now, createdAt: addingMinutes(index, to: now)))
        }
        try context.save()

        let session = try service.buildSession(in: context, now: now)

        XCTAssertEqual(session.newWordLimit, 20)
        XCTAssertEqual(session.items.count, 20)
        XCTAssertTrue(session.items.allSatisfy { $0.kind == .newWord })
    }

    func testCustomDailyNewWordLimitIsApplied() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)

        for index in 0..<8 {
            context.insert(makeWord("単語\(index)", state: .new, dueAt: now, createdAt: addingMinutes(index, to: now)))
        }
        try context.save()

        let session = try service.buildSession(in: context, now: now, dailyNewWordLimit: 3)

        XCTAssertEqual(session.newWordLimit, 3)
        XCTAssertEqual(session.items.count, 3)
        XCTAssertEqual(session.items.map { $0.word.japanese }, ["単語0", "単語1", "単語2"])
    }

    func testIntroducedNewWordsTodayCountAgainstDailyLimit() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)

        for index in 0..<19 {
            let word = makeWord("已学\(index)", state: .review, dueAt: addingDays(2, to: now), createdAt: addingDays(-2, to: now))
            word.reviewLogs = [
                ReviewLog(
                    reviewedAt: addingMinutes(index, to: now),
                    rating: .good,
                    previousState: .new,
                    nextState: .review,
                    previousIntervalDays: 0,
                    nextIntervalDays: 2,
                    scheduledDueAt: addingDays(2, to: now),
                    word: word
                )
            ]
            context.insert(word)
        }

        for index in 0..<5 {
            context.insert(makeWord("候补\(index)", state: .new, dueAt: now, createdAt: addingMinutes(index, to: now)))
        }
        try context.save()

        let session = try service.buildSession(in: context, now: now, dailyNewWordLimit: 20)

        XCTAssertEqual(session.newWordsAlreadyIntroducedToday, 19)
        XCTAssertEqual(session.items.count, 1)
        XCTAssertEqual(session.items.first?.word.japanese, "候补0")
        XCTAssertEqual(session.items.first?.kind, .newWord)
    }

    func testCompletedDailyNewWordLimitDoesNotAddMoreNewWordsOnReopen() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)

        for index in 0..<20 {
            let word = makeWord("今日完成\(index)", state: .review, dueAt: addingDays(2, to: now), createdAt: addingDays(-1, to: now))
            word.reviewLogs = [
                ReviewLog(
                    reviewedAt: addingMinutes(index, to: now),
                    rating: .good,
                    previousState: .new,
                    nextState: .review,
                    previousIntervalDays: 0,
                    nextIntervalDays: 2,
                    scheduledDueAt: addingDays(2, to: now),
                    word: word
                )
            ]
            context.insert(word)
        }

        for index in 0..<10 {
            context.insert(makeWord("未学\(index)", state: .new, dueAt: now, createdAt: addingMinutes(index, to: now)))
        }
        try context.save()

        let session = try service.buildSession(in: context, now: now, dailyNewWordLimit: 20)

        XCTAssertEqual(session.newWordsAlreadyIntroducedToday, 20)
        XCTAssertTrue(session.items.isEmpty)
        XCTAssertEqual(session.status, .completed)
    }

    func testRelearningWordRejoinsQueueWhenDue() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        let dueRelearning = makeWord("忘れる", state: .relearning, dueAt: now, createdAt: addingDays(-10, to: now))
        let futureRelearning = makeWord("影響", state: .relearning, dueAt: addingMinutes(10, to: now), createdAt: addingDays(-9, to: now))

        context.insert(dueRelearning)
        context.insert(futureRelearning)
        try context.save()

        let session = try service.buildSession(in: context, now: now, dailyNewWordLimit: 20)

        XCTAssertEqual(session.items.count, 1)
        XCTAssertEqual(session.items.first?.word.japanese, "忘れる")
        XCTAssertEqual(session.items.first?.kind, .dueReview)
    }

    func testQueueDoesNotContainDuplicateWords() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)

        context.insert(makeWord("確認", state: .review, dueAt: now, createdAt: addingDays(-2, to: now)))
        context.insert(makeWord("学生", state: .new, dueAt: now, createdAt: addingDays(-1, to: now)))
        try context.save()

        let session = try service.buildSession(in: context, now: now, dailyNewWordLimit: 20)
        let ids = session.items.map(\.id)

        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testRandomizedQueueKeepsReviewsBeforeNewWordsAndSameMembership() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        let reviewWord = makeWord("復習", state: .review, dueAt: now, createdAt: addingDays(-2, to: now))
        let newWord = makeWord("新規", state: .new, dueAt: now, createdAt: addingDays(-1, to: now))

        context.insert(reviewWord)
        context.insert(newWord)
        try context.save()

        let session = try service.buildSession(
            in: context,
            now: now,
            dailyNewWordLimit: 20,
            randomizesQueue: true
        )

        XCTAssertEqual(Set(session.items.map(\.id)), Set([reviewWord.id, newWord.id]))
        XCTAssertEqual(session.items.map(\.kind), [.dueReview, .newWord])
    }

    func testEmptyQueueReturnsCompletedStatus() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)

        context.insert(makeWord("未来", state: .review, dueAt: addingDays(1, to: now), createdAt: addingDays(-2, to: now)))
        context.insert(makeWord("暂停", state: .suspended, dueAt: now, createdAt: addingDays(-1, to: now)))
        try context.save()

        let session = try service.buildSession(in: context, now: now, dailyNewWordLimit: 20)

        XCTAssertTrue(session.items.isEmpty)
        XCTAssertTrue(session.isCompleted)
        XCTAssertEqual(session.status, .completed)
    }

    private func makeWord(
        _ japanese: String,
        state: LearningState,
        dueAt: Date,
        createdAt: Date
    ) -> VocabularyWord {
        let word = VocabularyWord(
            japanese: japanese,
            kana: japanese,
            chineseMeaning: japanese,
            jlptLevel: "N5",
            createdAt: createdAt,
            updatedAt: createdAt
        )
        word.progress = LearningProgress(
            state: state,
            dueAt: dueAt,
            createdAt: createdAt,
            updatedAt: createdAt,
            word: word
        )

        return word
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0
    ) -> Date {
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )

        guard let date = components.date else {
            XCTFail("Invalid test date: \(components)")
            return Date(timeIntervalSinceReferenceDate: 0)
        }

        return date
    }

    private func addingDays(_ days: Int, to date: Date) -> Date {
        guard let result = calendar.date(byAdding: .day, value: days, to: date) else {
            XCTFail("Failed to add days")
            return date
        }

        return result
    }

    private func addingHours(_ hours: Int, to date: Date) -> Date {
        guard let result = calendar.date(byAdding: .hour, value: hours, to: date) else {
            XCTFail("Failed to add hours")
            return date
        }

        return result
    }

    private func addingMinutes(_ minutes: Int, to date: Date) -> Date {
        guard let result = calendar.date(byAdding: .minute, value: minutes, to: date) else {
            XCTFail("Failed to add minutes")
            return date
        }

        return result
    }
}
