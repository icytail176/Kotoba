//
//  LearningProgress.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import Foundation
import SwiftData

@Model
final class LearningProgress {
    @Attribute(.unique) var id: UUID
    private var stateRawValue: String
    var dueAt: Date
    var intervalDays: Int
    var reviewCount: Int
    var lapseCount: Int
    var lastReviewedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    var word: VocabularyWord?

    var state: LearningState {
        get { LearningState(rawValue: stateRawValue) ?? .new }
        set {
            stateRawValue = newValue.rawValue
            updatedAt = Date()
        }
    }

    init(
        id: UUID = UUID(),
        state: LearningState = .new,
        dueAt: Date = Date(),
        intervalDays: Int = 0,
        reviewCount: Int = 0,
        lapseCount: Int = 0,
        lastReviewedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        word: VocabularyWord? = nil
    ) {
        self.id = id
        self.stateRawValue = state.rawValue
        self.dueAt = dueAt
        self.intervalDays = intervalDays
        self.reviewCount = reviewCount
        self.lapseCount = lapseCount
        self.lastReviewedAt = lastReviewedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.word = word
    }

}

enum StudyDuePolicy {
    nonisolated static func isDue(
        state: LearningState,
        dueAt: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        switch state {
        case .learning, .relearning:
            return dueAt <= now
        case .review:
            return calendar.startOfDay(for: dueAt) <= calendar.startOfDay(for: now)
        case .new, .suspended:
            return false
        }
    }

    static func isDue(
        progress: LearningProgress,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        isDue(state: progress.state, dueAt: progress.dueAt, now: now, calendar: calendar)
    }
}
