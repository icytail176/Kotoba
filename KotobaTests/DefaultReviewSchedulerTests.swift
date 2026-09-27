//
//  DefaultReviewSchedulerTests.swift
//  KotobaTests
//
//  Created by Codex on 2026/6/16.
//

import Foundation
import XCTest
@testable import Kotoba

final class DefaultReviewSchedulerTests: XCTestCase {
    private var calendar: Calendar!
    private var scheduler: DefaultReviewScheduler!

    override func setUp() {
        super.setUp()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        self.calendar = calendar
        scheduler = DefaultReviewScheduler(calendar: calendar)
    }

    override func tearDown() {
        calendar = nil
        scheduler = nil
        super.tearDown()
    }

    func testNewWordRatings() {
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)

        assertSchedule(
            currentState: .new,
            currentIntervalDays: 0,
            reviewCount: 0,
            lapseCount: 0,
            rating: .again,
            now: now,
            expectedState: .learning,
            expectedIntervalDays: 0,
            expectedNextReviewAt: addingMinutes(10, to: now),
            expectedDidLapse: false,
            expectedReviewCount: 1,
            expectedLapseCount: 0
        )
        assertNewWordRating(.hard, expectedDays: 1, now: now)
        assertNewWordRating(.good, expectedDays: 2, now: now)
        assertMastered(currentState: .new, currentDays: 0, reviewCount: 0, lapseCount: 0, now: now)
    }

    func testReviewWordRatings() {
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)

        assertSchedule(
            currentState: .review,
            currentIntervalDays: 10,
            reviewCount: 5,
            lapseCount: 1,
            rating: .again,
            now: now,
            expectedState: .relearning,
            expectedIntervalDays: 0,
            expectedNextReviewAt: addingMinutes(10, to: now),
            expectedDidLapse: true,
            expectedReviewCount: 6,
            expectedLapseCount: 2
        )
        assertReviewRating(.hard, currentDays: 10, expectedDays: 12, now: now)
        assertReviewRating(.good, currentDays: 10, expectedDays: 20, now: now)
        assertMastered(currentState: .review, currentDays: 10, reviewCount: 5, lapseCount: 1, now: now)
    }

    func testFuzzyRatingAt59DaysCapsTo60Days() {
        let now = makeDate(year: 2026, month: 6, day: 16)

        assertSchedule(
            currentState: .review,
            currentIntervalDays: 59,
            reviewCount: 12,
            lapseCount: 0,
            rating: .hard,
            now: now,
            expectedState: .review,
            expectedIntervalDays: 60,
            expectedNextReviewAt: addingDays(60, to: now),
            expectedDidLapse: false,
            expectedReviewCount: 13,
            expectedLapseCount: 0
        )
    }

    func testKnownRatingAt30DaysCapsTo60Days() {
        let now = makeDate(year: 2026, month: 6, day: 16)

        assertSchedule(
            currentState: .review,
            currentIntervalDays: 30,
            reviewCount: 12,
            lapseCount: 0,
            rating: .good,
            now: now,
            expectedState: .review,
            expectedIntervalDays: 60,
            expectedNextReviewAt: addingDays(60, to: now),
            expectedDidLapse: false,
            expectedReviewCount: 13,
            expectedLapseCount: 0
        )
    }

    func testEasyRatingSuspendsInsteadOfScheduling() {
        let now = makeDate(year: 2026, month: 6, day: 16)

        assertMastered(currentState: .review, currentDays: 30, reviewCount: 12, lapseCount: 0, now: now)
    }

    func testSuspendedWordRemainsSuspendedWithoutIncrementingCounts() {
        let now = makeDate(year: 2026, month: 6, day: 16)
        let first = scheduler.schedule(
            currentState: .suspended,
            currentIntervalDays: 60,
            reviewCount: 12,
            lapseCount: 0,
            rating: .easy,
            now: now
        )
        let second = scheduler.schedule(
            currentState: first.learningState,
            currentIntervalDays: first.intervalDays,
            reviewCount: first.reviewCount,
            lapseCount: first.lapseCount,
            rating: .easy,
            now: first.nextReviewAt
        )

        XCTAssertEqual(first.learningState, .suspended)
        XCTAssertEqual(first.intervalDays, 60)
        XCTAssertEqual(second.learningState, .suspended)
        XCTAssertEqual(second.reviewCount, 12)
        XCTAssertEqual(second.lapseCount, 0)
    }

    func testLapsedWordReappearsAfterTenMinutes() {
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 23, minute: 55)

        assertSchedule(
            currentState: .review,
            currentIntervalDays: 30,
            reviewCount: 9,
            lapseCount: 2,
            rating: .again,
            now: now,
            expectedState: .relearning,
            expectedIntervalDays: 0,
            expectedNextReviewAt: addingMinutes(10, to: now),
            expectedDidLapse: true,
            expectedReviewCount: 10,
            expectedLapseCount: 3
        )
    }

    func testTwoConsecutiveLapses() {
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        let first = scheduler.schedule(
            currentState: .review,
            currentIntervalDays: 12,
            reviewCount: 4,
            lapseCount: 1,
            rating: .again,
            now: now
        )
        let second = scheduler.schedule(
            currentState: first.learningState,
            currentIntervalDays: first.intervalDays,
            reviewCount: first.reviewCount,
            lapseCount: first.lapseCount,
            rating: .again,
            now: first.nextReviewAt
        )

        XCTAssertEqual(first.learningState, .relearning)
        XCTAssertEqual(first.nextReviewAt, addingMinutes(10, to: now))
        XCTAssertTrue(first.didLapse)
        XCTAssertEqual(first.lapseCount, 2)
        XCTAssertEqual(second.learningState, .relearning)
        XCTAssertEqual(second.intervalDays, 0)
        XCTAssertEqual(second.nextReviewAt, addingMinutes(10, to: first.nextReviewAt))
        XCTAssertTrue(second.didLapse)
        XCTAssertEqual(second.reviewCount, 6)
        XCTAssertEqual(second.lapseCount, 3)
    }

    func testSchedulingAcrossMonthBoundary() {
        let now = makeDate(year: 2026, month: 1, day: 31, hour: 8)

        assertSchedule(
            currentState: .new,
            currentIntervalDays: 0,
            reviewCount: 0,
            lapseCount: 0,
            rating: .good,
            now: now,
            expectedState: .review,
            expectedIntervalDays: 2,
            expectedNextReviewAt: makeDate(year: 2026, month: 2, day: 2, hour: 8),
            expectedDidLapse: false,
            expectedReviewCount: 1,
            expectedLapseCount: 0
        )
    }

    func testSchedulingAcrossYearBoundary() {
        let now = makeDate(year: 2026, month: 12, day: 31, hour: 23, minute: 55)

        assertSchedule(
            currentState: .review,
            currentIntervalDays: 1,
            reviewCount: 7,
            lapseCount: 0,
            rating: .hard,
            now: now,
            expectedState: .review,
            expectedIntervalDays: 2,
            expectedNextReviewAt: makeDate(year: 2027, month: 1, day: 2, hour: 23, minute: 55),
            expectedDidLapse: false,
            expectedReviewCount: 8,
            expectedLapseCount: 0
        )
    }

    private func assertNewWordRating(_ rating: ReviewRating, expectedDays: Int, now: Date) {
        assertSchedule(
            currentState: .new,
            currentIntervalDays: 0,
            reviewCount: 0,
            lapseCount: 0,
            rating: rating,
            now: now,
            expectedState: .review,
            expectedIntervalDays: expectedDays,
            expectedNextReviewAt: addingDays(expectedDays, to: now),
            expectedDidLapse: false,
            expectedReviewCount: 1,
            expectedLapseCount: 0
        )
    }

    private func assertReviewRating(_ rating: ReviewRating, currentDays: Int, expectedDays: Int, now: Date) {
        assertSchedule(
            currentState: .review,
            currentIntervalDays: currentDays,
            reviewCount: 5,
            lapseCount: 1,
            rating: rating,
            now: now,
            expectedState: .review,
            expectedIntervalDays: expectedDays,
            expectedNextReviewAt: addingDays(expectedDays, to: now),
            expectedDidLapse: false,
            expectedReviewCount: 6,
            expectedLapseCount: 1
        )
    }

    private func assertMastered(
        currentState: LearningState,
        currentDays: Int,
        reviewCount: Int,
        lapseCount: Int,
        now: Date
    ) {
        assertSchedule(
            currentState: currentState,
            currentIntervalDays: currentDays,
            reviewCount: reviewCount,
            lapseCount: lapseCount,
            rating: .easy,
            now: now,
            expectedState: .suspended,
            expectedIntervalDays: 0,
            expectedNextReviewAt: now,
            expectedDidLapse: false,
            expectedReviewCount: reviewCount + 1,
            expectedLapseCount: lapseCount
        )
    }

    private func assertSchedule(
        currentState: LearningState,
        currentIntervalDays: Int,
        reviewCount: Int,
        lapseCount: Int,
        rating: ReviewRating,
        now: Date,
        expectedState: LearningState,
        expectedIntervalDays: Int,
        expectedNextReviewAt: Date,
        expectedDidLapse: Bool,
        expectedReviewCount: Int,
        expectedLapseCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let result = scheduler.schedule(
            currentState: currentState,
            currentIntervalDays: currentIntervalDays,
            reviewCount: reviewCount,
            lapseCount: lapseCount,
            rating: rating,
            now: now
        )

        XCTAssertEqual(result.learningState, expectedState, file: file, line: line)
        XCTAssertEqual(result.intervalDays, expectedIntervalDays, file: file, line: line)
        XCTAssertEqual(result.nextReviewAt, expectedNextReviewAt, file: file, line: line)
        XCTAssertEqual(result.didLapse, expectedDidLapse, file: file, line: line)
        XCTAssertEqual(result.reviewCount, expectedReviewCount, file: file, line: line)
        XCTAssertEqual(result.lapseCount, expectedLapseCount, file: file, line: line)
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

    private func addingMinutes(_ minutes: Int, to date: Date) -> Date {
        guard let result = calendar.date(byAdding: .minute, value: minutes, to: date) else {
            XCTFail("Failed to add minutes")
            return date
        }

        return result
    }
}
