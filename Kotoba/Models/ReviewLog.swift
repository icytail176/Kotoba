//
//  ReviewLog.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import Foundation
import SwiftData

enum ReviewErrorType: String, Codable, CaseIterable, Identifiable, Sendable {
    case meaning
    case reading
    case spelling
    case expressionDirection
    case readingDirection

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meaning:
            return "意思"
        case .reading:
            return "读音"
        case .spelling:
            return "拼写"
        case .expressionDirection:
            return "写法方向"
        case .readingDirection:
            return "读音方向"
        }
    }
}

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
    var errorTypesRawValue: String = ""
    var typedAnswer: String?
    var expectedAnswer: String?
    var questionDirectionRawValue: String?
    var readingWrongCount: Int = 0
    var spellingWrongCount: Int = 0
    var repeatedWrongCount: Int = 0

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

    var errorTypes: [ReviewErrorType] {
        get {
            errorTypesRawValue
                .split(separator: ";")
                .compactMap { ReviewErrorType(rawValue: String($0)) }
        }
        set {
            errorTypesRawValue = newValue
                .map(\.rawValue)
                .sorted()
                .joined(separator: ";")
        }
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
        errorTypes: [ReviewErrorType] = [],
        typedAnswer: String? = nil,
        expectedAnswer: String? = nil,
        questionDirectionRawValue: String? = nil,
        readingWrongCount: Int = 0,
        spellingWrongCount: Int = 0,
        repeatedWrongCount: Int = 0,
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
        self.errorTypesRawValue = errorTypes.map(\.rawValue).sorted().joined(separator: ";")
        self.typedAnswer = typedAnswer
        self.expectedAnswer = expectedAnswer
        self.questionDirectionRawValue = questionDirectionRawValue
        self.readingWrongCount = max(0, readingWrongCount)
        self.spellingWrongCount = max(0, spellingWrongCount)
        self.repeatedWrongCount = max(0, repeatedWrongCount)
        self.word = word
    }
}
