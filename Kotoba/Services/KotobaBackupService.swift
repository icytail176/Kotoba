//
//  KotobaBackupService.swift
//  Kotoba
//
//  Created by Codex on 2026/6/18.
//

import Foundation
import SwiftData

nonisolated enum KotobaBackupImportStrategy: String, CaseIterable, Identifiable, Sendable {
    case merge
    case skipDuplicates
    case overwriteByID

    var id: String { rawValue }

    var title: String {
        switch self {
        case .merge: return "合并"
        case .skipDuplicates: return "跳过重复"
        case .overwriteByID: return "按 ID 覆盖"
        }
    }
}

// MARK: - Current backup schema

nonisolated struct KotobaBackupFile: Codable, Equatable, Sendable {
    let appVersion: String
    let schemaVersion: Int
    let exportedAt: Date
    var wordBooks: [BackupWordBook]
    var vocabularyWords: [BackupVocabularyWord]
    var learningProgress: [BackupLearningProgress]
    var reviewLogs: [BackupReviewLog]
}

nonisolated struct KotobaLearningProgressExportFile: Codable, Equatable, Sendable {
    let appVersion: String
    let schemaVersion: Int
    let exportedAt: Date
    var learningProgress: [BackupLearningProgress]
    var reviewLogs: [BackupReviewLog]
}

nonisolated struct BackupWordBook: Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let bookDescription: String
    let createdAt: Date
    let updatedAt: Date
    let isBuiltIn: Bool
}

nonisolated struct BackupVocabularyWord: Codable, Equatable, Sendable {
    let id: UUID
    let japanese: String
    let kana: String
    let chineseMeaning: String
    let partOfSpeech: String
    let jlptLevel: String
    let exampleJapanese: String
    let exampleChinese: String
    let tags: [String]
    let createdAt: Date
    let updatedAt: Date
    let isArchived: Bool
    let isFavorite: Bool
    let wordBookID: UUID?
    var loanwordSourceTerm: String? = nil
    var loanwordSourceLanguageCode: String? = nil
    var loanwordIsWasei: Bool? = nil
    var loanwordIsPartial: Bool? = nil
}

nonisolated struct BackupLearningProgress: Codable, Equatable, Sendable {
    let id: UUID
    let wordID: UUID?
    let state: LearningState
    let dueAt: Date
    let intervalDays: Int
    let reviewCount: Int
    let lapseCount: Int
    let lastReviewedAt: Date?
    let createdAt: Date
    let updatedAt: Date
}

nonisolated struct BackupReviewLog: Codable, Equatable, Sendable {
    let id: UUID
    let wordID: UUID?
    let reviewedAt: Date
    let rating: ReviewRating
    let previousState: LearningState
    let nextState: LearningState
    let previousIntervalDays: Int
    let nextIntervalDays: Int
    let scheduledDueAt: Date
    let errorTypes: [ReviewErrorType]
    let typedAnswer: String?
    let expectedAnswer: String?
    let questionDirectionRawValue: String?
    let readingWrongCount: Int
    let spellingWrongCount: Int
    let repeatedWrongCount: Int
}

// MARK: - Frozen V1 backup schema

nonisolated struct KotobaBackupFileV1: Codable {
    let appVersion: String
    let schemaVersion: Int
    let exportedAt: Date
    var wordBooks: [BackupWordBook]
    var vocabularyWords: [BackupVocabularyWord]
    var learningProgress: [BackupLearningProgressV1]
    var reviewLogs: [BackupReviewLogV1]
    var conjugationRecords: [BackupConjugationRecordV1]
}

nonisolated struct BackupLearningProgressV1: Codable {
    let id: UUID
    let wordID: UUID?
    let state: LearningState
    let dueAt: Date
    let intervalDays: Int
    let reviewLevel: Int
    let reviewCount: Int
    let lapseCount: Int
    let totalCorrectCount: Int
    let totalWrongCount: Int
    let consecutivePerfectCount: Int
    let consecutiveWrongCount: Int
    let meaningMastery: Int
    let readingMastery: Int
    let spellingMastery: Int
    let conjugationMastery: Int
    let firstLearnedAt: Date?
    let lastReviewedAt: Date?
    let createdAt: Date
    let updatedAt: Date
}

nonisolated enum BackupReviewErrorTypeV1: String, Codable, Equatable {
    case meaning
    case reading
    case spelling
    case expressionDirection
    case readingDirection
    case conjugation
}

nonisolated struct BackupReviewLogV1: Codable {
    let id: UUID
    let wordID: UUID?
    let reviewedAt: Date
    let rating: ReviewRating
    let previousState: LearningState
    let nextState: LearningState
    let previousIntervalDays: Int
    let nextIntervalDays: Int
    let scheduledDueAt: Date
    let errorTypes: [BackupReviewErrorTypeV1]
    let typedAnswer: String?
    let expectedAnswer: String?
    let questionDirectionRawValue: String?
    let formTypeRawValue: String?
    let reviewLevelBefore: Int
    let reviewLevelAfter: Int
    let readingWrongCount: Int
    let spellingWrongCount: Int
    let conjugationWrongCount: Int
    let repeatedWrongCount: Int
}

nonisolated struct BackupConjugationRecordV1: Codable {
    let id: UUID
    let wordID: UUID
    let conjugationClass: ConjugationClass
    let source: String
    let validationStatus: String
    let forms: [ConjugationForm]
    let modelName: String
    let generatedAt: Date
    let schemaVersion: Int
    let sourceFingerprint: String
    let markedIncorrect: Bool
}

nonisolated struct KotobaBackupImportResult: Equatable, Sendable {
    let insertedWordBookCount: Int
    let insertedWordCount: Int
    let insertedProgressCount: Int
    let insertedReviewLogCount: Int
    let updatedCount: Int
    let skippedCount: Int
}

nonisolated enum KotobaBackupValidationError: LocalizedError, Equatable, Sendable {
    case duplicateID(entity: String, id: UUID)
    case crossEntityIDConflict(id: UUID, firstEntity: String, secondEntity: String)
    case missingRequiredValue(entity: String, id: UUID, field: String)
    case missingReference(entity: String, id: UUID, field: String, referencedID: UUID?)
    case invalidNumber(entity: String, id: UUID, field: String, value: Int)
    case multipleProgress(wordID: UUID)

    var errorDescription: String? {
        switch self {
        case .duplicateID(let entity, let id):
            return "备份中的 \(entity) 包含重复 UUID：\(id.uuidString)。"
        case .crossEntityIDConflict(let id, let firstEntity, let secondEntity):
            return "UUID \(id.uuidString) 同时用于 \(firstEntity) 和 \(secondEntity)。"
        case .missingRequiredValue(let entity, let id, let field):
            return "备份中的 \(entity)（\(id.uuidString)）缺少必填字段 \(field)。"
        case .missingReference(let entity, let id, let field, let referencedID):
            return "备份中的 \(entity)（\(id.uuidString)）引用了不存在的 \(field)：\(referencedID?.uuidString ?? "nil")。"
        case .invalidNumber(let entity, let id, let field, let value):
            return "备份中的 \(entity)（\(id.uuidString)）字段 \(field) 的数值无效：\(value)。"
        case .multipleProgress(let wordID):
            return "单词 \(wordID.uuidString) 将对应多个 LearningProgress。"
        }
    }
}

nonisolated private struct BackupVersionEnvelope: Decodable {
    let schemaVersion: Int
}

nonisolated struct KotobaBackupService {
    typealias PhaseRecorder = (_ phase: String, _ elapsed: Duration) -> Void

    static let schemaVersion = 3

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let phaseRecorder: PhaseRecorder?
    private let beforeSave: (() throws -> Void)?

    init(
        phaseRecorder: PhaseRecorder? = nil,
        beforeSave: (() throws -> Void)? = nil
    ) {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.phaseRecorder = phaseRecorder
        self.beforeSave = beforeSave
    }

    func exportBackup(in context: ModelContext, exportedAt: Date = Date()) throws -> Data {
        try Self.encodeBackupSnapshot(makeBackup(in: context, exportedAt: exportedAt))
    }

    /// Encodes an immutable DTO graph and is safe to run away from MainActor.
    /// SwiftData models never cross the actor boundary.
    nonisolated static func encodeBackupSnapshot(_ backup: KotobaBackupFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    func exportLearningProgress(in context: ModelContext, exportedAt: Date = Date()) throws -> Data {
        let progress = try context.fetch(FetchDescriptor<LearningProgress>())
        let logs = try context.fetch(FetchDescriptor<ReviewLog>())
        return try encoder.encode(
            KotobaLearningProgressExportFile(
                appVersion: appVersion,
                schemaVersion: Self.schemaVersion,
                exportedAt: exportedAt,
                learningProgress: progress.map(backupProgress),
                reviewLogs: logs.map(backupReviewLog)
            )
        )
    }

    func decodeBackup(from data: Data) throws -> KotobaBackupFile {
        let version = try decoder.decode(BackupVersionEnvelope.self, from: data).schemaVersion
        switch version {
        case 1:
            return normalizedV2Backup(from: try decoder.decode(KotobaBackupFileV1.self, from: data))
        case 2, Self.schemaVersion:
            return try decoder.decode(KotobaBackupFile.self, from: data)
        default:
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Unsupported backup schema version: \(version).")
            )
        }
    }

    func importBackup(
        from data: Data,
        strategy: KotobaBackupImportStrategy,
        in context: ModelContext
    ) throws -> KotobaBackupImportResult {
        let backup = try measurePhase("decode") {
            try decodeBackup(from: data)
        }
        return try importBackup(backup, strategy: strategy, in: context)
    }

    func makeBackup(in context: ModelContext, exportedAt: Date = Date()) throws -> KotobaBackupFile {
        KotobaBackupFile(
            appVersion: appVersion,
            schemaVersion: Self.schemaVersion,
            exportedAt: exportedAt,
            wordBooks: try context.fetch(FetchDescriptor<WordBook>()).map(backupWordBook),
            vocabularyWords: try context.fetch(FetchDescriptor<VocabularyWord>()).map(backupWord),
            learningProgress: try context.fetch(FetchDescriptor<LearningProgress>()).map(backupProgress),
            reviewLogs: try context.fetch(FetchDescriptor<ReviewLog>()).map(backupReviewLog)
        )
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    private func normalizedV2Backup(from backup: KotobaBackupFileV1) -> KotobaBackupFile {
        KotobaBackupFile(
            appVersion: backup.appVersion,
            schemaVersion: backup.schemaVersion,
            exportedAt: backup.exportedAt,
            wordBooks: backup.wordBooks,
            vocabularyWords: backup.vocabularyWords,
            learningProgress: backup.learningProgress.map {
                BackupLearningProgress(
                    id: $0.id,
                    wordID: $0.wordID,
                    state: $0.state,
                    dueAt: $0.dueAt,
                    intervalDays: $0.intervalDays,
                    reviewCount: $0.reviewCount,
                    lapseCount: $0.lapseCount,
                    lastReviewedAt: $0.lastReviewedAt,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            reviewLogs: backup.reviewLogs.map {
                BackupReviewLog(
                    id: $0.id,
                    wordID: $0.wordID,
                    reviewedAt: $0.reviewedAt,
                    rating: $0.rating,
                    previousState: $0.previousState,
                    nextState: $0.nextState,
                    previousIntervalDays: $0.previousIntervalDays,
                    nextIntervalDays: $0.nextIntervalDays,
                    scheduledDueAt: $0.scheduledDueAt,
                    errorTypes: $0.errorTypes.compactMap { ReviewErrorType(rawValue: $0.rawValue) },
                    typedAnswer: $0.typedAnswer,
                    expectedAnswer: $0.expectedAnswer,
                    questionDirectionRawValue: $0.questionDirectionRawValue,
                    readingWrongCount: $0.readingWrongCount,
                    spellingWrongCount: $0.spellingWrongCount,
                    repeatedWrongCount: $0.repeatedWrongCount
                )
            }
        )
    }

    private func importBackup(
        _ backup: KotobaBackupFile,
        strategy: KotobaBackupImportStrategy,
        in context: ModelContext
    ) throws -> KotobaBackupImportResult {
        guard backup.schemaVersion <= Self.schemaVersion else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Backup schema version is newer than this app.")
            )
        }

        try validateAndBuildImportPlan(for: backup, strategy: strategy, in: context)

        var insertedWordBookCount = 0
        var insertedWordCount = 0
        var insertedProgressCount = 0
        var insertedReviewLogCount = 0
        var updatedCount = 0
        var skippedCount = 0

        do {
            try measurePhase("apply") {
                var wordBooksByID = Dictionary(
                    uniqueKeysWithValues: try context.fetch(FetchDescriptor<WordBook>()).map { ($0.id, $0) }
                )
                for item in backup.wordBooks {
                    if let existing = wordBooksByID[item.id] {
                        if strategy == .overwriteByID || (strategy == .merge && item.updatedAt > existing.updatedAt) {
                            apply(item, to: existing)
                            updatedCount += 1
                        } else {
                            skippedCount += 1
                        }
                    } else {
                        let wordBook = makeWordBook(from: item)
                        context.insert(wordBook)
                        wordBooksByID[wordBook.id] = wordBook
                        insertedWordBookCount += 1
                    }
                }

                var wordsByID = Dictionary(
                    uniqueKeysWithValues: try context.fetch(FetchDescriptor<VocabularyWord>()).map { ($0.id, $0) }
                )
                for item in backup.vocabularyWords {
                    let wordBook = item.wordBookID.flatMap { wordBooksByID[$0] }
                    if let existing = wordsByID[item.id] {
                        if strategy == .overwriteByID || (strategy == .merge && item.updatedAt > existing.updatedAt) {
                            apply(item, to: existing, wordBook: wordBook)
                            updatedCount += 1
                        } else {
                            skippedCount += 1
                        }
                    } else {
                        let word = makeWord(from: item, wordBook: wordBook)
                        context.insert(word)
                        wordsByID[word.id] = word
                        insertedWordCount += 1
                    }
                }

                var progressByID = Dictionary(
                    uniqueKeysWithValues: try context.fetch(FetchDescriptor<LearningProgress>()).map { ($0.id, $0) }
                )
                for item in backup.learningProgress {
                    let word = item.wordID.flatMap { wordsByID[$0] }
                    if let existing = progressByID[item.id] {
                        if strategy == .overwriteByID || (strategy == .merge && item.updatedAt > existing.updatedAt) {
                            apply(item, to: existing, word: word)
                            updatedCount += 1
                        } else {
                            skippedCount += 1
                        }
                    } else {
                        let progress = makeProgress(from: item, word: word)
                        context.insert(progress)
                        progressByID[progress.id] = progress
                        if word?.progress == nil {
                            word?.progress = progress
                        }
                        insertedProgressCount += 1
                    }
                }

                var logsByID = Dictionary(
                    uniqueKeysWithValues: try context.fetch(FetchDescriptor<ReviewLog>()).map { ($0.id, $0) }
                )
                for item in backup.reviewLogs {
                    let word = item.wordID.flatMap { wordsByID[$0] }
                    if let existing = logsByID[item.id] {
                        if strategy == .overwriteByID {
                            apply(item, to: existing, word: word)
                            updatedCount += 1
                        } else {
                            skippedCount += 1
                        }
                    } else {
                        let log = makeReviewLog(from: item, word: word)
                        context.insert(log)
                        logsByID[log.id] = log
                        word?.reviewLogs.append(log)
                        insertedReviewLogCount += 1
                    }
                }
            }

            try measurePhase("save") {
                try beforeSave?()
                try context.save()
            }
        } catch {
            context.rollback()
            throw error
        }

        return KotobaBackupImportResult(
            insertedWordBookCount: insertedWordBookCount,
            insertedWordCount: insertedWordCount,
            insertedProgressCount: insertedProgressCount,
            insertedReviewLogCount: insertedReviewLogCount,
            updatedCount: updatedCount,
            skippedCount: skippedCount
        )
    }

    /// Phase 1 of backup restore. This method is deliberately read-only: it
    /// validates the decoded DTO graph and the graph that would exist after the
    /// selected conflict strategy before Phase 2 mutates SwiftData.
    private func validateAndBuildImportPlan(
        for backup: KotobaBackupFile,
        strategy: KotobaBackupImportStrategy,
        in context: ModelContext
    ) throws {
        let incomingEntityByID = try measurePhase("preflight") {
            try requireUniqueIDs(backup.wordBooks.map(\.id), entity: "WordBook")
            try requireUniqueIDs(backup.vocabularyWords.map(\.id), entity: "VocabularyWord")
            try requireUniqueIDs(backup.learningProgress.map(\.id), entity: "LearningProgress")
            try requireUniqueIDs(backup.reviewLogs.map(\.id), entity: "ReviewLog")

            var incomingEntityByID: [UUID: String] = [:]
            try register(backup.wordBooks.map(\.id), entity: "WordBook", in: &incomingEntityByID)
            try register(backup.vocabularyWords.map(\.id), entity: "VocabularyWord", in: &incomingEntityByID)
            try register(backup.learningProgress.map(\.id), entity: "LearningProgress", in: &incomingEntityByID)
            try register(backup.reviewLogs.map(\.id), entity: "ReviewLog", in: &incomingEntityByID)

            for book in backup.wordBooks {
                try requireText(book.name, entity: "WordBook", id: book.id, field: "name")
            }
            for word in backup.vocabularyWords {
                try requireText(word.japanese, entity: "VocabularyWord", id: word.id, field: "expression")
                try requireText(word.kana, entity: "VocabularyWord", id: word.id, field: "reading")
                try requireText(word.chineseMeaning, entity: "VocabularyWord", id: word.id, field: "meaningChinese")
            }
            for progress in backup.learningProgress {
                try requireNonnegative(progress.intervalDays, entity: "LearningProgress", id: progress.id, field: "intervalDays")
                try requireNonnegative(progress.reviewCount, entity: "LearningProgress", id: progress.id, field: "reviewCount")
                try requireNonnegative(progress.lapseCount, entity: "LearningProgress", id: progress.id, field: "lapseCount")
            }
            for log in backup.reviewLogs {
                try requireNonnegative(log.previousIntervalDays, entity: "ReviewLog", id: log.id, field: "previousIntervalDays")
                try requireNonnegative(log.nextIntervalDays, entity: "ReviewLog", id: log.id, field: "nextIntervalDays")
                try requireNonnegative(log.readingWrongCount, entity: "ReviewLog", id: log.id, field: "readingWrongCount")
                try requireNonnegative(log.spellingWrongCount, entity: "ReviewLog", id: log.id, field: "spellingWrongCount")
                try requireNonnegative(log.repeatedWrongCount, entity: "ReviewLog", id: log.id, field: "repeatedWrongCount")
            }
            return incomingEntityByID
        }

        try measurePhase("plan") {
            let localBooks = try context.fetch(FetchDescriptor<WordBook>())
            let localWords = try context.fetch(FetchDescriptor<VocabularyWord>())
            let localProgress = try context.fetch(FetchDescriptor<LearningProgress>())
            let localLogs = try context.fetch(FetchDescriptor<ReviewLog>())
        let localBookByID = Dictionary(uniqueKeysWithValues: localBooks.map { ($0.id, $0) })
        let localWordByID = Dictionary(uniqueKeysWithValues: localWords.map { ($0.id, $0) })
        let localProgressByID = Dictionary(uniqueKeysWithValues: localProgress.map { ($0.id, $0) })
        let localLogByID = Dictionary(uniqueKeysWithValues: localLogs.map { ($0.id, $0) })

        var localEntityByID: [UUID: String] = [:]
        for (entity, ids) in [
            ("WordBook", localBooks.map(\.id)),
            ("VocabularyWord", localWords.map(\.id)),
            ("LearningProgress", localProgress.map(\.id)),
            ("ReviewLog", localLogs.map(\.id))
        ] {
            for id in ids where localEntityByID[id] == nil { localEntityByID[id] = entity }
        }
        for (id, entity) in incomingEntityByID {
            if let localEntity = localEntityByID[id], localEntity != entity {
                throw KotobaBackupValidationError.crossEntityIDConflict(
                    id: id,
                    firstEntity: localEntity,
                    secondEntity: entity
                )
            }
        }

        let finalBookIDs = Set(localBookByID.keys).union(backup.wordBooks.map(\.id))
        let finalWordIDs = Set(localWordByID.keys).union(backup.vocabularyWords.map(\.id))

        for word in backup.vocabularyWords {
            guard let bookID = word.wordBookID, finalBookIDs.contains(bookID) else {
                throw KotobaBackupValidationError.missingReference(
                    entity: "VocabularyWord",
                    id: word.id,
                    field: "wordBookID",
                    referencedID: word.wordBookID
                )
            }
        }
        for progress in backup.learningProgress {
            guard let wordID = progress.wordID, finalWordIDs.contains(wordID) else {
                throw KotobaBackupValidationError.missingReference(
                    entity: "LearningProgress",
                    id: progress.id,
                    field: "wordID",
                    referencedID: progress.wordID
                )
            }
        }
        for log in backup.reviewLogs {
            guard let wordID = log.wordID, finalWordIDs.contains(wordID) else {
                throw KotobaBackupValidationError.missingReference(
                    entity: "ReviewLog",
                    id: log.id,
                    field: "wordID",
                    referencedID: log.wordID
                )
            }
        }

        // Compute the effective progress relationship after skip/overwrite/merge.
        // This catches both duplicate progress inside the backup and collisions
        // between an incoming progress and a different local progress.
        var finalWordIDByProgressID: [UUID: UUID] = [:]
        for progress in localProgress {
            if let wordID = progress.word?.id { finalWordIDByProgressID[progress.id] = wordID }
        }
        for item in backup.learningProgress {
            guard let incomingWordID = item.wordID else { continue }
            if let existing = localProgressByID[item.id] {
                if strategy == .overwriteByID || (strategy == .merge && item.updatedAt > existing.updatedAt) {
                    finalWordIDByProgressID[item.id] = incomingWordID
                }
            } else {
                finalWordIDByProgressID[item.id] = incomingWordID
            }
        }
        var progressCountByWordID: [UUID: Int] = [:]
        for wordID in finalWordIDByProgressID.values {
            progressCountByWordID[wordID, default: 0] += 1
            if progressCountByWordID[wordID, default: 0] > 1 {
                throw KotobaBackupValidationError.multipleProgress(wordID: wordID)
            }
        }

        // Keep these lookups part of the preflight so UUID collisions are fully
        // resolved before any mutation begins.
            _ = localLogByID
        }
    }

    private func measurePhase<T>(
        _ name: String,
        operation: () throws -> T
    ) rethrows -> T {
        let start = ContinuousClock.now
        defer { phaseRecorder?(name, start.duration(to: .now)) }
        return try operation()
    }

    private func requireUniqueIDs(_ ids: [UUID], entity: String) throws {
        var seen = Set<UUID>()
        for id in ids where !seen.insert(id).inserted {
            throw KotobaBackupValidationError.duplicateID(entity: entity, id: id)
        }
    }

    private func register(_ ids: [UUID], entity: String, in entities: inout [UUID: String]) throws {
        for id in ids {
            if let existing = entities[id], existing != entity {
                throw KotobaBackupValidationError.crossEntityIDConflict(
                    id: id,
                    firstEntity: existing,
                    secondEntity: entity
                )
            }
            entities[id] = entity
        }
    }

    private func requireText(_ value: String, entity: String, id: UUID, field: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw KotobaBackupValidationError.missingRequiredValue(entity: entity, id: id, field: field)
        }
    }

    private func requireNonnegative(_ value: Int, entity: String, id: UUID, field: String) throws {
        guard value >= 0 else {
            throw KotobaBackupValidationError.invalidNumber(entity: entity, id: id, field: field, value: value)
        }
    }

    private func backupWordBook(_ wordBook: WordBook) -> BackupWordBook {
        BackupWordBook(
            id: wordBook.id,
            name: wordBook.name,
            bookDescription: wordBook.bookDescription,
            createdAt: wordBook.createdAt,
            updatedAt: wordBook.updatedAt,
            isBuiltIn: wordBook.isBuiltIn
        )
    }

    private func backupWord(_ word: VocabularyWord) -> BackupVocabularyWord {
        BackupVocabularyWord(
            id: word.id,
            japanese: word.japanese,
            kana: word.kana,
            chineseMeaning: word.chineseMeaning,
            partOfSpeech: word.partOfSpeech,
            jlptLevel: word.jlptLevel,
            exampleJapanese: word.exampleJapanese,
            exampleChinese: word.exampleChinese,
            tags: word.tags,
            createdAt: word.createdAt,
            updatedAt: word.updatedAt,
            isArchived: word.isArchived,
            isFavorite: word.isFavorite,
            wordBookID: word.wordBook?.id,
            loanwordSourceTerm: word.loanwordSourceTerm,
            loanwordSourceLanguageCode: word.loanwordSourceLanguageCode,
            loanwordIsWasei: word.loanwordIsWasei,
            loanwordIsPartial: word.loanwordIsPartial
        )
    }

    private func backupProgress(_ progress: LearningProgress) -> BackupLearningProgress {
        BackupLearningProgress(
            id: progress.id,
            wordID: progress.word?.id,
            state: progress.state,
            dueAt: progress.dueAt,
            intervalDays: progress.intervalDays,
            reviewCount: progress.reviewCount,
            lapseCount: progress.lapseCount,
            lastReviewedAt: progress.lastReviewedAt,
            createdAt: progress.createdAt,
            updatedAt: progress.updatedAt
        )
    }

    private func backupReviewLog(_ log: ReviewLog) -> BackupReviewLog {
        BackupReviewLog(
            id: log.id,
            wordID: log.word?.id,
            reviewedAt: log.reviewedAt,
            rating: log.rating,
            previousState: log.previousState,
            nextState: log.nextState,
            previousIntervalDays: log.previousIntervalDays,
            nextIntervalDays: log.nextIntervalDays,
            scheduledDueAt: log.scheduledDueAt,
            errorTypes: log.errorTypes,
            typedAnswer: log.typedAnswer,
            expectedAnswer: log.expectedAnswer,
            questionDirectionRawValue: log.questionDirectionRawValue,
            readingWrongCount: log.readingWrongCount,
            spellingWrongCount: log.spellingWrongCount,
            repeatedWrongCount: log.repeatedWrongCount
        )
    }

    private func makeWordBook(from backup: BackupWordBook) -> WordBook {
        WordBook(
            id: backup.id,
            name: backup.name,
            bookDescription: backup.bookDescription,
            createdAt: backup.createdAt,
            updatedAt: backup.updatedAt,
            isBuiltIn: backup.isBuiltIn
        )
    }

    private func makeWord(from backup: BackupVocabularyWord, wordBook: WordBook?) -> VocabularyWord {
        VocabularyWord(
            id: backup.id,
            japanese: backup.japanese,
            kana: backup.kana,
            chineseMeaning: backup.chineseMeaning,
            partOfSpeech: backup.partOfSpeech,
            jlptLevel: backup.jlptLevel,
            exampleJapanese: backup.exampleJapanese,
            exampleChinese: backup.exampleChinese,
            tags: backup.tags,
            createdAt: backup.createdAt,
            updatedAt: backup.updatedAt,
            isArchived: backup.isArchived,
            isFavorite: backup.isFavorite,
            loanwordSourceTerm: backup.loanwordSourceTerm,
            loanwordSourceLanguageCode: backup.loanwordSourceLanguageCode,
            loanwordIsWasei: backup.loanwordIsWasei ?? false,
            loanwordIsPartial: backup.loanwordIsPartial ?? false,
            wordBook: wordBook
        )
    }

    private func makeProgress(from backup: BackupLearningProgress, word: VocabularyWord?) -> LearningProgress {
        LearningProgress(
            id: backup.id,
            state: backup.state,
            dueAt: backup.dueAt,
            intervalDays: backup.intervalDays,
            reviewCount: backup.reviewCount,
            lapseCount: backup.lapseCount,
            lastReviewedAt: backup.lastReviewedAt,
            createdAt: backup.createdAt,
            updatedAt: backup.updatedAt,
            word: word
        )
    }

    private func makeReviewLog(from backup: BackupReviewLog, word: VocabularyWord?) -> ReviewLog {
        ReviewLog(
            id: backup.id,
            reviewedAt: backup.reviewedAt,
            rating: backup.rating,
            previousState: backup.previousState,
            nextState: backup.nextState,
            previousIntervalDays: backup.previousIntervalDays,
            nextIntervalDays: backup.nextIntervalDays,
            scheduledDueAt: backup.scheduledDueAt,
            errorTypes: backup.errorTypes,
            typedAnswer: backup.typedAnswer,
            expectedAnswer: backup.expectedAnswer,
            questionDirectionRawValue: backup.questionDirectionRawValue,
            readingWrongCount: backup.readingWrongCount,
            spellingWrongCount: backup.spellingWrongCount,
            repeatedWrongCount: backup.repeatedWrongCount,
            word: word
        )
    }

    private func apply(_ backup: BackupWordBook, to wordBook: WordBook) {
        wordBook.name = backup.name
        wordBook.bookDescription = backup.bookDescription
        wordBook.updatedAt = backup.updatedAt
        wordBook.isBuiltIn = backup.isBuiltIn
    }

    private func apply(_ backup: BackupVocabularyWord, to word: VocabularyWord, wordBook: WordBook?) {
        word.japanese = backup.japanese
        word.kana = backup.kana
        word.chineseMeaning = backup.chineseMeaning
        word.partOfSpeech = backup.partOfSpeech
        word.jlptLevel = backup.jlptLevel
        word.exampleJapanese = backup.exampleJapanese
        word.exampleChinese = backup.exampleChinese
        word.tags = backup.tags
        word.updatedAt = backup.updatedAt
        word.isArchived = backup.isArchived
        word.isFavorite = backup.isFavorite
        word.loanwordSourceTerm = backup.loanwordSourceTerm
        word.loanwordSourceLanguageCode = backup.loanwordSourceLanguageCode
        word.loanwordIsWasei = backup.loanwordIsWasei ?? false
        word.loanwordIsPartial = backup.loanwordIsPartial ?? false
        word.wordBook = wordBook
    }

    private func apply(_ backup: BackupLearningProgress, to progress: LearningProgress, word: VocabularyWord?) {
        progress.state = backup.state
        progress.dueAt = backup.dueAt
        progress.intervalDays = backup.intervalDays
        progress.reviewCount = backup.reviewCount
        progress.lapseCount = backup.lapseCount
        progress.lastReviewedAt = backup.lastReviewedAt
        progress.updatedAt = backup.updatedAt
        progress.word = word
        if word?.progress == nil {
            word?.progress = progress
        }
    }

    private func apply(_ backup: BackupReviewLog, to log: ReviewLog, word: VocabularyWord?) {
        log.reviewedAt = backup.reviewedAt
        log.rating = backup.rating
        log.previousState = backup.previousState
        log.nextState = backup.nextState
        log.previousIntervalDays = backup.previousIntervalDays
        log.nextIntervalDays = backup.nextIntervalDays
        log.scheduledDueAt = backup.scheduledDueAt
        log.errorTypes = backup.errorTypes
        log.typedAnswer = backup.typedAnswer
        log.expectedAnswer = backup.expectedAnswer
        log.questionDirectionRawValue = backup.questionDirectionRawValue
        log.readingWrongCount = backup.readingWrongCount
        log.spellingWrongCount = backup.spellingWrongCount
        log.repeatedWrongCount = backup.repeatedWrongCount
        log.word = word
    }
}
