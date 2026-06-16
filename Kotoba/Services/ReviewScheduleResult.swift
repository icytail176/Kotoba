//
//  ReviewScheduleResult.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import Foundation

struct ReviewScheduleResult: Equatable {
    let learningState: LearningState
    let intervalDays: Int
    let nextReviewAt: Date
    let didLapse: Bool
    let reviewCount: Int
    let lapseCount: Int
}
