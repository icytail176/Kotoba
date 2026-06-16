//
//  StudyQueueService.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import Foundation
import SwiftData

struct StudyQueueService {
    static let defaultDailyNewWordLimit = 20

    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func buildSession(
        in context: ModelContext,
        now: Date,
        dailyNewWordLimit: Int = Self.defaultDailyNewWordLimit,
        randomizesQueue: Bool = false
    ) throws -> StudySession {
        let words = try context.fetch(FetchDescriptor<VocabularyWord>())
        let activeWords = words.filter { !$0.isArchived }
        let dueItems = dueReviewItems(from: activeWords, now: now)
        let newWordsAlreadyIntroducedToday = countNewWordsIntroducedToday(from: activeWords, now: now)
        let remainingNewWordSlots = max(0, dailyNewWordLimit - newWordsAlreadyIntroducedToday)
        let newItems = newWordItems(
            from: activeWords,
            excluding: Set(dueItems.map(\.id)),
            limit: remainingNewWordSlots,
            now: now
        )
        let items = randomizesQueue ? dueItems.shuffled() + newItems.shuffled() : dueItems + newItems

        return StudySession(
            status: items.isEmpty ? .completed : .ready,
            items: items,
            newWordLimit: dailyNewWordLimit,
            newWordsAlreadyIntroducedToday: newWordsAlreadyIntroducedToday
        )
    }

    private func dueReviewItems(from words: [VocabularyWord], now: Date) -> [StudySession.Item] {
        words.compactMap { word -> StudySession.Item? in
            guard let progress = word.progress,
                  isReviewQueueState(progress.state),
                  progress.dueAt <= now else {
                return nil
            }

            return StudySession.Item(
                id: word.id,
                word: word,
                kind: .dueReview,
                dueAt: progress.dueAt
            )
        }
        .sorted {
            if $0.dueAt == $1.dueAt {
                return $0.word.createdAt < $1.word.createdAt
            }

            return $0.dueAt < $1.dueAt
        }
    }

    private func newWordItems(
        from words: [VocabularyWord],
        excluding excludedIDs: Set<UUID>,
        limit: Int,
        now: Date
    ) -> [StudySession.Item] {
        guard limit > 0 else {
            return []
        }

        return words
            .filter { word in
                guard !excludedIDs.contains(word.id),
                      let progress = word.progress else {
                    return false
                }

                return progress.state == .new
            }
            .sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.japanese < $1.japanese
                }

                return $0.createdAt < $1.createdAt
            }
            .prefix(limit)
            .map { word in
                StudySession.Item(
                    id: word.id,
                    word: word,
                    kind: .newWord,
                    dueAt: word.progress?.dueAt ?? now
                )
            }
    }

    private func countNewWordsIntroducedToday(from words: [VocabularyWord], now: Date) -> Int {
        var introducedWordIDs = Set<UUID>()

        for word in words {
            guard !introducedWordIDs.contains(word.id) else {
                continue
            }

            if word.reviewLogs.contains(where: { log in
                log.previousState == .new && calendar.isDate(log.reviewedAt, inSameDayAs: now)
            }) {
                introducedWordIDs.insert(word.id)
            }
        }

        return introducedWordIDs.count
    }

    private func isReviewQueueState(_ state: LearningState) -> Bool {
        switch state {
        case .learning, .review, .relearning:
            true
        case .new, .suspended:
            false
        }
    }
}
