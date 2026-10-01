//
//  StudyStatisticsCalculatorTests.swift
//  KotobaTests
//

import SwiftData
import XCTest
@testable import Kotoba

final class StudyStatisticsCalculatorTests: XCTestCase {
    @MainActor
    func testServiceReadsCompleteCoreHistory() async throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let word = VocabularyWord(japanese: "確認", kana: "かくにん", chineseMeaning: "确认", jlptLevel: "N3")
        let log = ReviewLog(
            reviewedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            rating: .again,
            previousState: .review,
            nextState: .relearning,
            previousIntervalDays: 5,
            nextIntervalDays: 0,
            scheduledDueAt: Date(timeIntervalSinceReferenceDate: 1_600),
            word: word
        )
        context.insert(word)
        context.insert(log)
        try context.save()

        let input = try await StudyStatisticsService().makeInput(in: container)

        XCTAssertEqual(input.words, [.init(id: word.id, expression: "確認", reading: "かくにん", meaningChinese: "确认")])
        XCTAssertEqual(input.logs.first?.id, log.id)
    }

    func testCountsTodayAndRecentSevenDaysInProvidedTimeZone() throws {
        let calendar = try makeCalendar()
        let now = try makeDate(day: 10, calendar: calendar)
        let wordID = UUID()
        let input = StudyStatisticsInput(
            logs: [
                makeLog(wordID: wordID, at: now, state: .new),
                makeLog(wordID: wordID, at: now, state: .review),
                makeLog(wordID: wordID, at: try addDays(-6, to: now, calendar: calendar), state: .review),
                makeLog(wordID: wordID, at: try addDays(-7, to: now, calendar: calendar), state: .review)
            ],
            words: [makeWord(id: wordID)]
        )

        let result = StudyStatisticsCalculator().calculate(input: input, calendar: calendar, now: now)

        XCTAssertEqual(result.todayNewWordCount, 1)
        XCTAssertEqual(result.todayReviewCount, 1)
        XCTAssertEqual(result.totalLearnedWordCount, 1)
        XCTAssertEqual(result.recentDailyActivity.count, 7)
        XCTAssertEqual(result.recentDailyActivity.reduce(0) { $0 + $1.totalCount }, 3)
    }

    func testStreakUsesHistoryBeyondThirtyDays() throws {
        let calendar = try makeCalendar()
        let now = try makeDate(day: 10, calendar: calendar)
        let wordID = UUID()
        let logs = try (0..<45).map { offset in
            makeLog(wordID: wordID, at: try addDays(-offset, to: now, calendar: calendar), state: .review)
        }

        let result = StudyStatisticsCalculator().calculate(
            input: .init(logs: logs, words: [makeWord(id: wordID)]),
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(result.currentStreakDays, 45)
    }

    func testHardestWordsAreLimitedToTen() throws {
        let calendar = try makeCalendar()
        let now = try makeDate(day: 10, calendar: calendar)
        let words = (0..<12).map { makeWord(id: UUID(), expression: "词\($0)") }
        let logs = words.enumerated().flatMap { index, word in
            (0...index).map { _ in makeLog(wordID: word.id, at: now, state: .review, rating: .again) }
        }

        let result = StudyStatisticsCalculator().calculate(
            input: .init(logs: logs, words: words),
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(result.topLapsedWords.count, 10)
        XCTAssertEqual(result.topLapsedWords.first?.lapseCount, 12)
    }

    func testSevenAndThirtyDayRangesHonorBoundariesAndExcludeFutureLogs() throws {
        let calendar = try makeCalendar()
        let now = try makeDate(day: 30, calendar: calendar)
        let wordID = UUID()
        let logs = try [-30, -29, -7, -6, 0, 1].map { offset in
            makeLog(wordID: wordID, at: try addDays(offset, to: now, calendar: calendar), state: .review)
        }
        let input = StudyStatisticsInput(logs: logs, words: [makeWord(id: wordID)])
        let calculator = StudyStatisticsCalculator()

        let sevenDays = calculator.calculate(
            input: input,
            calendar: calendar,
            now: now,
            range: .sevenDays
        )
        let thirtyDays = calculator.calculate(
            input: input,
            calendar: calendar,
            now: now,
            range: .thirtyDays
        )

        XCTAssertEqual(sevenDays.periodFormalReviewCount, 2)
        XCTAssertEqual(sevenDays.recentDailyActivity.count, 7)
        XCTAssertEqual(thirtyDays.periodFormalReviewCount, 4)
        XCTAssertEqual(thirtyDays.recentDailyActivity.count, 30)
    }

    func testPeriodStatisticsSeparateRatingsManualAndAutomaticMastery() throws {
        let calendar = try makeCalendar()
        let now = try makeDate(day: 10, calendar: calendar)
        let words = (0..<5).map { makeWord(id: UUID(), expression: "词\($0)") }
        let logs = [
            makeLog(wordID: words[0].id, at: now, state: .review, rating: .again),
            makeLog(wordID: words[1].id, at: now, state: .review, rating: .hard),
            makeLog(wordID: words[2].id, at: now, state: .review, rating: .good),
            makeLog(wordID: words[3].id, at: now, state: .review, rating: .good, nextState: .suspended),
            makeLog(wordID: words[4].id, at: now, state: .review, rating: .easy, nextState: .suspended)
        ]

        let result = StudyStatisticsCalculator().calculate(
            input: .init(logs: logs, words: words),
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(result.periodFormalReviewCount, 5)
        XCTAssertEqual(result.ratingDistribution.againCount, 1)
        XCTAssertEqual(result.ratingDistribution.hardCount, 1)
        XCTAssertEqual(result.ratingDistribution.goodCount, 2)
        XCTAssertEqual(result.ratingDistribution.masteredCount, 1)
        XCTAssertEqual(result.periodManualMasteryCount, 1)
        XCTAssertEqual(result.periodAutomaticMasteryCount, 1)
    }

    func testNewlyLearnedUsesEarliestFormalLogWithinSelectedRange() throws {
        let calendar = try makeCalendar()
        let now = try makeDate(day: 30, calendar: calendar)
        let oldWord = makeWord(id: UUID(), expression: "旧词")
        let recentWord = makeWord(id: UUID(), expression: "新词")
        let logs = try [
            makeLog(wordID: oldWord.id, at: addDays(-20, to: now, calendar: calendar), state: .new),
            makeLog(wordID: oldWord.id, at: now, state: .review),
            makeLog(wordID: recentWord.id, at: addDays(-2, to: now, calendar: calendar), state: .new)
        ]
        let input = StudyStatisticsInput(logs: logs, words: [oldWord, recentWord])

        let sevenDays = StudyStatisticsCalculator().calculate(
            input: input,
            calendar: calendar,
            now: now,
            range: .sevenDays
        )
        let thirtyDays = StudyStatisticsCalculator().calculate(
            input: input,
            calendar: calendar,
            now: now,
            range: .thirtyDays
        )

        XCTAssertEqual(sevenDays.periodNewlyLearnedWordCount, 1)
        XCTAssertEqual(thirtyDays.periodNewlyLearnedWordCount, 2)
    }

    func testSpellingFirstPassUsesEligiblePersistedWrongCountsAndShowsNoSampleState() throws {
        let calendar = try makeCalendar()
        let now = try makeDate(day: 10, calendar: calendar)
        let kanaWord = makeWord(id: UUID(), expression: "テレビ")
        let kanjiWord = makeWord(id: UUID(), expression: "確認")
        let masteredWord = makeWord(id: UUID(), expression: "完了")
        let logs = [
            makeLog(wordID: kanaWord.id, at: now, state: .new, hasSpellingDiagnostics: true, spellingWrongCount: 0),
            makeLog(
                wordID: kanjiWord.id,
                at: now,
                state: .review,
                hasSpellingDiagnostics: true,
                readingWrongCount: 0,
                spellingWrongCount: 1
            ),
            makeLog(
                wordID: masteredWord.id,
                at: now,
                state: .review,
                rating: .easy,
                nextState: .suspended
            )
        ]

        let result = StudyStatisticsCalculator().calculate(
            input: .init(logs: logs, words: [kanaWord, kanjiWord, masteredWord]),
            calendar: calendar,
            now: now
        )
        XCTAssertEqual(result.spellingFirstPassAccuracy.eligibleCount, 3)
        XCTAssertEqual(result.spellingFirstPassAccuracy.passedCount, 2)
        XCTAssertEqual(result.spellingFirstPassAccuracy.displayText, "67%")

        let noSample = StudyStatisticsCalculator().calculate(
            input: .init(logs: [logs[2]], words: [masteredWord]),
            calendar: calendar,
            now: now
        )
        XCTAssertEqual(noSample.spellingFirstPassAccuracy.eligibleCount, 0)
        XCTAssertEqual(noSample.spellingFirstPassAccuracy.displayText, "—")
    }

    private func makeLog(
        wordID: UUID,
        at date: Date,
        state: LearningState,
        rating: ReviewRating = .good,
        nextState: LearningState? = nil,
        hasSpellingDiagnostics: Bool = false,
        readingWrongCount: Int = 0,
        spellingWrongCount: Int = 0
    ) -> StudyLogSnapshot {
        StudyLogSnapshot(
            id: UUID(),
            wordID: wordID,
            reviewedAt: date,
            rating: rating,
            previousState: state,
            nextState: nextState ?? (rating == .easy ? .suspended : .review),
            hasSpellingDiagnostics: hasSpellingDiagnostics,
            readingWrongCount: readingWrongCount,
            spellingWrongCount: spellingWrongCount
        )
    }

    private func makeWord(id: UUID, expression: String = "确认") -> StudyWordSnapshot {
        StudyWordSnapshot(id: id, expression: expression, reading: "かくにん", meaningChinese: "确认")
    }

    private func makeCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        return calendar
    }

    private func makeDate(day: Int, calendar: Calendar) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: day, hour: 10)))
    }

    private func addDays(_ days: Int, to date: Date, calendar: Calendar) throws -> Date {
        try XCTUnwrap(calendar.date(byAdding: .day, value: days, to: date))
    }
}
