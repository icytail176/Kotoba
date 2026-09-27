//
//  StudyStatisticsService.swift
//  Kotoba
//

import Foundation
import SwiftData

struct StudyStatisticsSnapshot: Equatable, Sendable {
    let input: StudyStatisticsInput
    let logCount: Int
    let wordCount: Int
    let usedCache: Bool
}

struct StudyStatisticsService {
    private static let cache = StudyStatisticsMemoryCache()

    nonisolated init() {}

    nonisolated func makeInput(in container: ModelContainer) async throws -> StudyStatisticsInput {
        try await makeSnapshot(in: container).input
    }

    nonisolated func makeSnapshot(in container: ModelContainer) async throws -> StudyStatisticsSnapshot {
        let store = StudyStatisticsSnapshotStore(modelContainer: container)
        let signature = try await store.signature()

        if let cached = await Self.cache.snapshot(signature: signature) {
            return cached
        }

        let input = try await store.makeInput()
        let snapshot = StudyStatisticsSnapshot(
            input: input,
            logCount: input.logs.count,
            wordCount: input.words.count,
            usedCache: false
        )
        await Self.cache.store(snapshot, signature: signature)
        return snapshot
    }

    nonisolated static func invalidateCache() {
        Task { await cache.removeAll() }
    }
}

private actor StudyStatisticsMemoryCache {
    private var cached: (signature: String, snapshot: StudyStatisticsSnapshot)?

    func snapshot(signature: String) -> StudyStatisticsSnapshot? {
        guard let cached, cached.signature == signature else { return nil }
        return StudyStatisticsSnapshot(
            input: cached.snapshot.input,
            logCount: cached.snapshot.logCount,
            wordCount: cached.snapshot.wordCount,
            usedCache: true
        )
    }

    func store(_ snapshot: StudyStatisticsSnapshot, signature: String) {
        cached = (signature, snapshot)
    }

    func removeAll() { cached = nil }
}

@ModelActor
actor StudyStatisticsSnapshotStore {
    func signature() throws -> String {
        var logDescriptor = FetchDescriptor<ReviewLog>(sortBy: [SortDescriptor(\.reviewedAt, order: .reverse)])
        let logCount = try modelContext.fetchCount(logDescriptor)
        logDescriptor.fetchLimit = 1
        let latestReviewedAt = try modelContext.fetch(logDescriptor).first?.reviewedAt

        var wordDescriptor = FetchDescriptor<VocabularyWord>(predicate: #Predicate { !$0.isArchived })
        let wordCount = try modelContext.fetchCount(wordDescriptor)
        wordDescriptor.fetchLimit = 1
        wordDescriptor.sortBy = [SortDescriptor(\.updatedAt, order: .reverse)]
        let latestWordUpdatedAt = try modelContext.fetch(wordDescriptor).first?.updatedAt

        return "\(logCount)|\(latestReviewedAt?.timeIntervalSinceReferenceDate ?? -1)|\(wordCount)|\(latestWordUpdatedAt?.timeIntervalSinceReferenceDate ?? -1)"
    }

    func makeInput() throws -> StudyStatisticsInput {
        let logs = try modelContext.fetch(FetchDescriptor<ReviewLog>(sortBy: [SortDescriptor(\.reviewedAt)]))
        let words = try modelContext.fetch(FetchDescriptor<VocabularyWord>(predicate: #Predicate { !$0.isArchived }))

        return StudyStatisticsInput(
            logs: logs.map {
                StudyLogSnapshot(
                    id: $0.id,
                    wordID: $0.word?.id,
                    reviewedAt: $0.reviewedAt,
                    rating: $0.rating,
                    previousState: $0.previousState
                )
            },
            words: words.map {
                StudyWordSnapshot(
                    id: $0.id,
                    expression: $0.japanese,
                    reading: $0.kana,
                    meaningChinese: $0.chineseMeaning
                )
            }
        )
    }
}
