//
//  ReviewScheduler.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import Foundation

protocol ReviewScheduler {
    func schedule(
        currentState: LearningState,
        currentIntervalDays: Int,
        reviewCount: Int,
        lapseCount: Int,
        rating: ReviewRating,
        now: Date
    ) -> ReviewScheduleResult
}
