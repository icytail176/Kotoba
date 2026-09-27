//
//  DefaultReviewScheduler.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import Foundation

struct DefaultReviewScheduler: ReviewScheduler {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func schedule(
        currentState: LearningState,
        currentIntervalDays: Int,
        reviewCount: Int,
        lapseCount: Int,
        rating: ReviewRating,
        now: Date
    ) -> ReviewScheduleResult {
        let nextReviewCount = reviewCount + 1

        switch currentState {
        case .new:
            return scheduleInitialLearning(
                rating: rating,
                now: now,
                reviewCount: nextReviewCount,
                lapseCount: lapseCount
            )
        case .learning:
            return scheduleLearningStep(
                learningStateForAgain: .learning,
                rating: rating,
                now: now,
                didLapseOnAgain: false,
                reviewCount: nextReviewCount,
                lapseCount: lapseCount
            )
        case .review:
            return scheduleReview(
                currentIntervalDays: currentIntervalDays,
                rating: rating,
                now: now,
                reviewCount: nextReviewCount,
                lapseCount: lapseCount
            )
        case .relearning:
            return scheduleLearningStep(
                learningStateForAgain: .relearning,
                rating: rating,
                now: now,
                didLapseOnAgain: true,
                reviewCount: nextReviewCount,
                lapseCount: lapseCount
            )
        case .suspended:
            return ReviewScheduleResult(
                learningState: .suspended,
                intervalDays: max(0, currentIntervalDays),
                nextReviewAt: now,
                didLapse: false,
                reviewCount: reviewCount,
                lapseCount: lapseCount
            )
        }
    }

    private func scheduleInitialLearning(
        rating: ReviewRating,
        now: Date,
        reviewCount: Int,
        lapseCount: Int
    ) -> ReviewScheduleResult {
        switch rating {
        case .again:
            return minuteResult(
                state: .learning,
                now: now,
                didLapse: false,
                reviewCount: reviewCount,
                lapseCount: lapseCount
            )
        case .hard:
            return dayResult(days: 1, now: now, reviewCount: reviewCount, lapseCount: lapseCount)
        case .good:
            return dayResult(days: 2, now: now, reviewCount: reviewCount, lapseCount: lapseCount)
        case .easy:
            return masteredResult(now: now, reviewCount: reviewCount, lapseCount: lapseCount)
        }
    }

    private func scheduleLearningStep(
        learningStateForAgain: LearningState,
        rating: ReviewRating,
        now: Date,
        didLapseOnAgain: Bool,
        reviewCount: Int,
        lapseCount: Int
    ) -> ReviewScheduleResult {
        switch rating {
        case .again:
            return minuteResult(
                state: learningStateForAgain,
                now: now,
                didLapse: didLapseOnAgain,
                reviewCount: reviewCount,
                lapseCount: didLapseOnAgain ? lapseCount + 1 : lapseCount
            )
        case .hard:
            return dayResult(days: 1, now: now, reviewCount: reviewCount, lapseCount: lapseCount)
        case .good:
            return dayResult(days: 2, now: now, reviewCount: reviewCount, lapseCount: lapseCount)
        case .easy:
            return masteredResult(now: now, reviewCount: reviewCount, lapseCount: lapseCount)
        }
    }

    private func scheduleReview(
        currentIntervalDays: Int,
        rating: ReviewRating,
        now: Date,
        reviewCount: Int,
        lapseCount: Int
    ) -> ReviewScheduleResult {
        switch rating {
        case .again:
            return minuteResult(
                state: .relearning,
                now: now,
                didLapse: true,
                reviewCount: reviewCount,
                lapseCount: lapseCount + 1
            )
        case .hard:
            return dayResult(
                days: multipliedIntervalDays(currentIntervalDays, multiplier: 1.2),
                now: now,
                reviewCount: reviewCount,
                lapseCount: lapseCount
            )
        case .good:
            return dayResult(
                days: multipliedIntervalDays(currentIntervalDays, multiplier: 2.0),
                now: now,
                reviewCount: reviewCount,
                lapseCount: lapseCount
            )
        case .easy:
            return masteredResult(now: now, reviewCount: reviewCount, lapseCount: lapseCount)
        }
    }

    private func masteredResult(
        now: Date,
        reviewCount: Int,
        lapseCount: Int
    ) -> ReviewScheduleResult {
        ReviewScheduleResult(
            learningState: .suspended,
            intervalDays: 0,
            nextReviewAt: now,
            didLapse: false,
            reviewCount: reviewCount,
            lapseCount: lapseCount
        )
    }

    private func multipliedIntervalDays(_ currentIntervalDays: Int, multiplier: Double) -> Int {
        let positiveInterval = max(0, currentIntervalDays)
        let multiplied = Int(ceil(Double(positiveInterval) * multiplier))
        return cappedDayInterval(multiplied)
    }

    private func minuteResult(
        state: LearningState,
        now: Date,
        didLapse: Bool,
        reviewCount: Int,
        lapseCount: Int
    ) -> ReviewScheduleResult {
        ReviewScheduleResult(
            learningState: state,
            intervalDays: 0,
            nextReviewAt: addingMinutes(10, to: now),
            didLapse: didLapse,
            reviewCount: reviewCount,
            lapseCount: lapseCount
        )
    }

    private func dayResult(
        days: Int,
        now: Date,
        reviewCount: Int,
        lapseCount: Int
    ) -> ReviewScheduleResult {
        let intervalDays = cappedDayInterval(days)

        return ReviewScheduleResult(
            learningState: .review,
            intervalDays: intervalDays,
            nextReviewAt: addingDays(intervalDays, to: now),
            didLapse: false,
            reviewCount: reviewCount,
            lapseCount: lapseCount
        )
    }

    private func cappedDayInterval(_ days: Int) -> Int {
        min(max(1, days), AppSettings.maximumReviewIntervalDays)
    }

    private func addingMinutes(_ minutes: Int, to date: Date) -> Date {
        calendar.date(byAdding: .minute, value: minutes, to: date) ?? date.addingTimeInterval(TimeInterval(minutes * 60))
    }

    private func addingDays(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date.addingTimeInterval(TimeInterval(days * 24 * 60 * 60))
    }
}
