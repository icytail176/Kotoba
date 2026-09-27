//
//  KotobaSchemaV1.swift
//  Kotoba
//
//  Frozen schema for stores created before data-model simplification.
//

import Foundation
import SwiftData

enum KotobaSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static let models: [any PersistentModel.Type] = [
        WordBook.self,
        VocabularyWord.self,
        LearningProgress.self,
        ReviewLog.self,
        ConjugationRecord.self,
        SpeechTuningRecord.self
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
        var reviewLevel: Int = 0
        var reviewCount: Int
        var lapseCount: Int
        var totalCorrectCount: Int = 0
        var totalWrongCount: Int = 0
        var consecutivePerfectCount: Int = 0
        var consecutiveWrongCount: Int = 0
        var meaningMastery: Int = 0
        var readingMastery: Int = 0
        var spellingMastery: Int = 0
        var conjugationMastery: Int = 0
        var firstLearnedAt: Date?
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
            reviewLevel: Int = 0,
            reviewCount: Int = 0,
            lapseCount: Int = 0,
            totalCorrectCount: Int = 0,
            totalWrongCount: Int = 0,
            consecutivePerfectCount: Int = 0,
            consecutiveWrongCount: Int = 0,
            meaningMastery: Int = 0,
            readingMastery: Int = 0,
            spellingMastery: Int = 0,
            conjugationMastery: Int = 0,
            firstLearnedAt: Date? = nil,
            lastReviewedAt: Date? = nil,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            word: VocabularyWord? = nil
        ) {
            self.id = id
            self.stateRawValue = state.rawValue
            self.dueAt = dueAt
            self.intervalDays = intervalDays
            self.reviewLevel = reviewLevel
            self.reviewCount = reviewCount
            self.lapseCount = lapseCount
            self.totalCorrectCount = totalCorrectCount
            self.totalWrongCount = totalWrongCount
            self.consecutivePerfectCount = consecutivePerfectCount
            self.consecutiveWrongCount = consecutiveWrongCount
            self.meaningMastery = meaningMastery
            self.readingMastery = readingMastery
            self.spellingMastery = spellingMastery
            self.conjugationMastery = conjugationMastery
            self.firstLearnedAt = firstLearnedAt
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
        var formTypeRawValue: String?
        var reviewLevelBefore: Int = 0
        var reviewLevelAfter: Int = 0
        var readingWrongCount: Int = 0
        var spellingWrongCount: Int = 0
        var conjugationWrongCount: Int = 0
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
                errorTypesRawValue = newValue.map(\.rawValue).sorted().joined(separator: ";")
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
            errorTypesRawValue: String = "",
            typedAnswer: String? = nil,
            expectedAnswer: String? = nil,
            questionDirectionRawValue: String? = nil,
            formTypeRawValue: String? = nil,
            reviewLevelBefore: Int = 0,
            reviewLevelAfter: Int = 0,
            readingWrongCount: Int = 0,
            spellingWrongCount: Int = 0,
            conjugationWrongCount: Int = 0,
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
            self.formTypeRawValue = formTypeRawValue
            self.reviewLevelBefore = reviewLevelBefore
            self.reviewLevelAfter = reviewLevelAfter
            self.readingWrongCount = readingWrongCount
            self.spellingWrongCount = spellingWrongCount
            self.conjugationWrongCount = conjugationWrongCount
            self.repeatedWrongCount = repeatedWrongCount
            self.word = word
        }
    }

    @Model
    final class ConjugationRecord {
        @Attribute(.unique) var id: UUID
        var wordID: UUID
        private var conjugationClassRawValue: String
        private var sourceRawValue: String
        private var validationStatusRawValue: String
        private var formsData: Data
        var modelName: String
        var generatedAt: Date
        var schemaVersion: Int
        var sourceFingerprint: String
        var markedIncorrect: Bool

        init(
            id: UUID = UUID(),
            wordID: UUID,
            conjugationClassRawValue: String,
            sourceRawValue: String,
            validationStatusRawValue: String,
            formsData: Data = Data(),
            modelName: String = "",
            generatedAt: Date = Date(),
            schemaVersion: Int = 1,
            sourceFingerprint: String,
            markedIncorrect: Bool = false
        ) {
            self.id = id
            self.wordID = wordID
            self.conjugationClassRawValue = conjugationClassRawValue
            self.sourceRawValue = sourceRawValue
            self.validationStatusRawValue = validationStatusRawValue
            self.formsData = formsData
            self.modelName = modelName
            self.generatedAt = generatedAt
            self.schemaVersion = schemaVersion
            self.sourceFingerprint = sourceFingerprint
            self.markedIncorrect = markedIncorrect
        }
    }

    @Model
    final class SpeechTuningRecord {
        @Attribute(.unique) var id: UUID
        var wordID: UUID
        var wordBookID: UUID?
        private var engineRawValue: String
        var speakerID: Int
        private var purposeRawValue: String
        var baseText: String
        var readingText: String
        var audioQueryJSON: Data?
        var accentPhrasesJSON: Data?
        var speedScale: Double
        var pitchScale: Double
        var intonationScale: Double
        var volumeScale: Double
        var prePhonemeLength: Double
        var postPhonemeLength: Double
        var isManualEdited: Bool
        var needsReview: Bool
        var createdAt: Date
        var updatedAt: Date

        init(
            id: UUID = UUID(),
            wordID: UUID,
            wordBookID: UUID? = nil,
            engineRawValue: String = "voicevox",
            speakerID: Int,
            purposeRawValue: String = "word",
            baseText: String,
            readingText: String = "",
            audioQueryJSON: Data? = nil,
            accentPhrasesJSON: Data? = nil,
            speedScale: Double = 1.0,
            pitchScale: Double = 0.0,
            intonationScale: Double = 1.0,
            volumeScale: Double = 1.0,
            prePhonemeLength: Double = 0.1,
            postPhonemeLength: Double = 0.1,
            isManualEdited: Bool = false,
            needsReview: Bool = false,
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.wordID = wordID
            self.wordBookID = wordBookID
            self.engineRawValue = engineRawValue
            self.speakerID = speakerID
            self.purposeRawValue = purposeRawValue
            self.baseText = baseText
            self.readingText = readingText
            self.audioQueryJSON = audioQueryJSON
            self.accentPhrasesJSON = accentPhrasesJSON
            self.speedScale = speedScale
            self.pitchScale = pitchScale
            self.intonationScale = intonationScale
            self.volumeScale = volumeScale
            self.prePhonemeLength = prePhonemeLength
            self.postPhonemeLength = postPhonemeLength
            self.isManualEdited = isManualEdited
            self.needsReview = needsReview
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }
}
