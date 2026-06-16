//
//  StudyStatisticsCalculatorTests.swift
//  KotobaTests
//
//  Created by Codex on 2026/6/16.
//

import XCTest

final class StudyStatisticsCalculatorTests: XCTestCase {
    private let calculator = StudyStatisticsCalculator()

    func testRecentActivityGroupsDatesUsingProvidedCalendarAndTimeZone() throws {
        let calendar = try makeCalendar(timeZoneIdentifier: "Asia/Shanghai")
        let wordID = UUID()
        let input = StudyStatisticsInput(
            logs: [
                makeLog(
                    wordID: wordID,
                    reviewedAt: try makeDate(
                        year: 2026,
                        month: 6,
                        day: 16,
                        hour: 0,
                        minute: 30,
                        timeZoneIdentifier: "Asia/Shanghai"
                    ),
                    rating: .good,
                    previousState: .new
                ),
                makeLog(
                    wordID: wordID,
                    reviewedAt: try makeDate(
                        year: 2026,
                        month: 6,
                        day: 16,
                        hour: 23,
                        minute: 30,
                        timeZoneIdentifier: "Asia/Shanghai"
                    ),
                    rating: .hard,
                    previousState: .review
                )
            ],
            words: [
                makeWord(id: wordID, expression: "勉強", jlptLevel: "N5")
            ]
        )
        let now = try makeDate(
            year: 2026,
            month: 6,
            day: 16,
            hour: 23,
            minute: 45,
            timeZoneIdentifier: "Asia/Shanghai"
        )

        let statistics = calculator.calculate(input: input, calendar: calendar, now: now)
        let activity = try XCTUnwrap(statistics.recentDailyActivity.last)

        XCTAssertTrue(calendar.isDate(activity.day, inSameDayAs: now))
        XCTAssertEqual(activity.totalCount, 2)
        XCTAssertEqual(activity.newWordCount, 1)
        XCTAssertEqual(activity.reviewCount, 1)
        XCTAssertEqual(statistics.todayNewWordCount, 1)
        XCTAssertEqual(statistics.todayReviewCount, 1)
    }

    func testCurrentStreakCountsConsecutiveDaysEndingTodayAndDeduplicatesLogs() throws {
        let calendar = try makeCalendar(timeZoneIdentifier: "Asia/Shanghai")
        let now = try makeDate(
            year: 2026,
            month: 1,
            day: 10,
            hour: 9,
            minute: 0,
            timeZoneIdentifier: "Asia/Shanghai"
        )
        let duplicateID = UUID()
        let wordID = UUID()
        let input = StudyStatisticsInput(
            logs: [
                makeLog(id: duplicateID, wordID: wordID, reviewedAt: now),
                makeLog(id: duplicateID, wordID: wordID, reviewedAt: now),
                makeLog(wordID: wordID, reviewedAt: try date(byAddingDays: -1, to: now, calendar: calendar)),
                makeLog(wordID: wordID, reviewedAt: try date(byAddingDays: -2, to: now, calendar: calendar)),
                makeLog(wordID: wordID, reviewedAt: try date(byAddingDays: -4, to: now, calendar: calendar))
            ],
            words: [
                makeWord(id: wordID, expression: "確認", jlptLevel: "N3")
            ]
        )

        let statistics = calculator.calculate(input: input, calendar: calendar, now: now)

        XCTAssertEqual(statistics.totalReviewCount, 4)
        XCTAssertEqual(statistics.currentStreakDays, 3)
    }

    func testCurrentStreakIsZeroWhenTodayHasNoActivity() throws {
        let calendar = try makeCalendar(timeZoneIdentifier: "Asia/Shanghai")
        let now = try makeDate(
            year: 2026,
            month: 1,
            day: 10,
            hour: 9,
            minute: 0,
            timeZoneIdentifier: "Asia/Shanghai"
        )
        let wordID = UUID()
        let input = StudyStatisticsInput(
            logs: [
                makeLog(wordID: wordID, reviewedAt: try date(byAddingDays: -1, to: now, calendar: calendar)),
                makeLog(wordID: wordID, reviewedAt: try date(byAddingDays: -2, to: now, calendar: calendar))
            ],
            words: [
                makeWord(id: wordID, expression: "復習", jlptLevel: "N4")
            ]
        )

        let statistics = calculator.calculate(input: input, calendar: calendar, now: now)

        XCTAssertEqual(statistics.currentStreakDays, 0)
    }

    private func makeLog(
        id: UUID = UUID(),
        wordID: UUID?,
        reviewedAt: Date,
        rating: ReviewRating = .good,
        previousState: LearningState = .review,
        nextState: LearningState = .review
    ) -> StudyLogSnapshot {
        StudyLogSnapshot(
            id: id,
            wordID: wordID,
            reviewedAt: reviewedAt,
            rating: rating,
            previousState: previousState,
            nextState: nextState
        )
    }

    private func makeWord(
        id: UUID,
        expression: String,
        jlptLevel: String
    ) -> StudyWordSnapshot {
        StudyWordSnapshot(
            id: id,
            expression: expression,
            reading: "",
            meaningChinese: "",
            jlptLevel: jlptLevel,
            isArchived: false
        )
    }

    private func makeCalendar(timeZoneIdentifier: String) throws -> Calendar {
        let timeZone = try XCTUnwrap(TimeZone(identifier: timeZoneIdentifier))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        timeZoneIdentifier: String
    ) throws -> Date {
        let timeZone = try XCTUnwrap(TimeZone(identifier: timeZoneIdentifier))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        return try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )))
    }

    private func date(byAddingDays days: Int, to date: Date, calendar: Calendar) throws -> Date {
        try XCTUnwrap(calendar.date(byAdding: .day, value: days, to: date))
    }
}
