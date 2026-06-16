//
//  ReviewLog.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import Foundation
import SwiftData

@Model
final class ReviewLog {
    @Attribute(.unique) var id: UUID
    var reviewedAt: Date
    private var ratingRawValue: String
    private var previousStateRawValue: String
    private var nextStateRawValue: String
    var previousIntervalDays: Int
    var nextIntervalDays: Int
    var scheduledDueAt: Date

    var word: VocabularyWord?

    var rating: ReviewRating {
        get { ReviewRating(rawValue: ratingRawValue) ?? .again }
        set { ratingRawValue = newValue.rawValue }
    }

    var previousState: LearningState {
        get { LearningState(rawValue: previousStateRawValue) ?? .new }
        set { previousStateRawValue = newValue.rawValue }
    }

    var nextState: LearningState {
        get { LearningState(rawValue: nextStateRawValue) ?? .new }
        set { nextStateRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        reviewedAt: Date = Date(),
        rating: ReviewRating,
        previousState: LearningState,
        nextState: LearningState,
        previousIntervalDays: Int,
        nextIntervalDays: Int,
        scheduledDueAt: Date,
        word: VocabularyWord? = nil
    ) {
        self.id = id
        self.reviewedAt = reviewedAt
        self.ratingRawValue = rating.rawValue
        self.previousStateRawValue = previousState.rawValue
        self.nextStateRawValue = nextState.rawValue
        self.previousIntervalDays = previousIntervalDays
        self.nextIntervalDays = nextIntervalDays
        self.scheduledDueAt = scheduledDueAt
        self.word = word
    }
}
