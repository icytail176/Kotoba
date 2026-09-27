//
//  KotobaSchemaV2.swift
//  Kotoba
//
//  Frozen schema used by stores created after the core-model simplification.
//

import Foundation
import SwiftData

enum KotobaSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static let models: [any PersistentModel.Type] = [
        WordBook.self,
        VocabularyWord.self,
        LearningProgress.self,
        ReviewLog.self
    ]

    @Model
    final class WordBook {
        @Attribute(.unique) var id: UUID
        var name: String
        var bookDescription: String
        var createdAt: Date
        var updatedAt: Date
        var isBuiltIn: Bool

        @Relationship(deleteRule: .cascade, inverse: \VocabularyWord.wordBook)
        var words: [VocabularyWord]

        init(
            id: UUID = UUID(),
            name: String,
            bookDescription: String = "",
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            isBuiltIn: Bool = false,
            words: [VocabularyWord] = []
        ) {
            self.id = id
            self.name = name
            self.bookDescription = bookDescription
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.isBuiltIn = isBuiltIn
            self.words = words
        }
    }

    @Model
    final class VocabularyWord {
        @Attribute(.unique) var id: UUID
        var japanese: String
        var kana: String
        var chineseMeaning: String
        var partOfSpeech: String
        var jlptLevel: String
        var exampleJapanese: String
        var exampleChinese: String
        var tags: [String]
        var createdAt: Date
        var updatedAt: Date
        var isArchived: Bool
        var isFavorite: Bool
        var wordBook: WordBook?

        @Relationship(deleteRule: .cascade, inverse: \LearningProgress.word)
        var progress: LearningProgress?

        @Relationship(deleteRule: .cascade, inverse: \ReviewLog.word)
        var reviewLogs: [ReviewLog]

        init(
            id: UUID = UUID(),
            japanese: String,
            kana: String,
            chineseMeaning: String,
            partOfSpeech: String = "",
            jlptLevel: String,
            exampleJapanese: String = "",
            exampleChinese: String = "",
            tags: [String] = [],
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            isArchived: Bool = false,
            isFavorite: Bool = false,
            wordBook: WordBook? = nil,
            progress: LearningProgress? = nil,
            reviewLogs: [ReviewLog] = []
        ) {
            self.id = id
            self.japanese = japanese
            self.kana = kana
            self.chineseMeaning = chineseMeaning
            self.partOfSpeech = partOfSpeech
            self.jlptLevel = jlptLevel
            self.exampleJapanese = exampleJapanese
            self.exampleChinese = exampleChinese
            self.tags = tags
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.isArchived = isArchived
            self.isFavorite = isFavorite
            self.wordBook = wordBook
            self.progress = progress
            self.reviewLogs = reviewLogs
        }
    }

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
            set { stateRawValue = newValue.rawValue }
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

        init(
            id: UUID = UUID(),
            reviewedAt: Date = Date(),
            rating: ReviewRating,
            previousState: LearningState,
            nextState: LearningState,
            previousIntervalDays: Int,
            nextIntervalDays: Int,
            scheduledDueAt: Date,
            errorTypesRawValue: String = "",
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
            self.errorTypesRawValue = errorTypesRawValue
            self.typedAnswer = typedAnswer
            self.expectedAnswer = expectedAnswer
            self.questionDirectionRawValue = questionDirectionRawValue
            self.readingWrongCount = readingWrongCount
            self.spellingWrongCount = spellingWrongCount
            self.repeatedWrongCount = repeatedWrongCount
            self.word = word
        }
    }
}
