//
//  StudyQueueService.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import Foundation
import SwiftData

struct StudyQueueService {
    private let calendar: Calendar
    private let shuffle: ([StudySession.Item]) -> [StudySession.Item]

    init(
        calendar: Calendar = .current,
        shuffle: @escaping ([StudySession.Item]) -> [StudySession.Item] = { $0.shuffled() }
    ) {
        self.calendar = calendar
        self.shuffle = shuffle
    }

    func buildSession(
        in context: ModelContext,
        wordBook: WordBook? = nil,
        mode: StudySession.Mode = .mixed,
        now: Date,
        studyGroupNewWordCount: Int = AppSettings.defaultStudyGroupNewWordCount,
        reviewGroupWordCount: Int = AppSettings.defaultReviewGroupWordCount,
        randomizesQueue: Bool = true
    ) throws -> StudySession {
        try PerformanceTrace.measure("Study queue build") {
            let clampedStudyGroupNewWordCount = AppSettings.clampedStudyGroupNewWordCount(studyGroupNewWordCount)
            let clampedReviewGroupWordCount = AppSettings.clampedReviewGroupWordCount(reviewGroupWordCount)
            let words: [VocabularyWord]
            if let wordBook {
                words = wordBook.words
            } else {
                words = try context.fetch(FetchDescriptor<VocabularyWord>())
            }
            let activeWords = scopedActiveWords(words, wordBook: wordBook)
            let dueCandidates = mode == .newWordsOnly
                ? []
                : dueReviewItems(from: activeWords, now: now)
            let newCandidates: [StudySession.Item]

            switch mode {
            case .mixed, .newWordsOnly:
                newCandidates = newWordItems(
                    from: activeWords,
                    excluding: Set(dueCandidates.map(\.id)),
                    now: now
                )
            case .dueReviewsOnly:
                newCandidates = []
            }

            let items: [StudySession.Item]
            if randomizesQueue {
                items = selectRandomizedGroup(
                    from: shuffle(dueCandidates + newCandidates),
                    newWordGroupLimit: clampedStudyGroupNewWordCount,
                    reviewLimit: clampedReviewGroupWordCount
                )
            } else {
                items = Array(dueCandidates.prefix(clampedReviewGroupWordCount))
                    + Array(newCandidates.prefix(clampedStudyGroupNewWordCount))
            }

            return StudySession(
                status: items.isEmpty ? .completed : .ready,
                items: items
            )
        }
    }

    private func scopedActiveWords(_ words: [VocabularyWord], wordBook: WordBook?) -> [VocabularyWord] {
        words.filter { word in
            guard !word.isArchived else {
                return false
            }

            guard let wordBook else {
                return true
            }

            return word.wordBook?.id == wordBook.id
        }
    }

    private func dueReviewItems(from words: [VocabularyWord], now: Date) -> [StudySession.Item] {
        return words.compactMap { word -> StudySession.Item? in
            guard let progress = word.progress,
                  isReviewQueueState(progress.state),
                  StudyDuePolicy.isDue(progress: progress, now: now, calendar: calendar) else {
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
            let lhsDueDate = calendar.startOfDay(for: $0.dueAt)
            let rhsDueDate = calendar.startOfDay(for: $1.dueAt)
            if lhsDueDate != rhsDueDate {
                return lhsDueDate < rhsDueDate
            }

            if $0.dueAt != $1.dueAt {
                return $0.dueAt < $1.dueAt
            }

            if $0.word.createdAt == $1.word.createdAt {
                return $0.word.japanese < $1.word.japanese
            }

            return $0.word.createdAt < $1.word.createdAt
        }
    }

    private func newWordItems(
        from words: [VocabularyWord],
        excluding excludedIDs: Set<UUID>,
        now: Date
    ) -> [StudySession.Item] {
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
            .map { word in
                StudySession.Item(
                    id: word.id,
                    word: word,
                    kind: .newWord,
                    dueAt: word.progress?.dueAt ?? now
                )
            }
    }

    private func selectRandomizedGroup(
        from candidates: [StudySession.Item],
        newWordGroupLimit: Int,
        reviewLimit: Int
    ) -> [StudySession.Item] {
        var selected: [StudySession.Item] = []
        var selectedNewWordCount = 0
        var selectedReviewCount = 0
        let availableNewWordCount = candidates.lazy.filter { $0.kind == .newWord }.count
        let availableReviewCount = candidates.count - availableNewWordCount
        let targetNewWordCount = min(newWordGroupLimit, availableNewWordCount)
        let targetReviewCount = min(reviewLimit, availableReviewCount)

        for item in candidates {
            switch item.kind {
            case .newWord where selectedNewWordCount < targetNewWordCount:
                selected.append(item)
                selectedNewWordCount += 1
            case .dueReview where selectedReviewCount < targetReviewCount:
                selected.append(item)
                selectedReviewCount += 1
            default:
                continue
            }

            if selectedNewWordCount == targetNewWordCount,
               selectedReviewCount == targetReviewCount {
                break
            }
        }

        return selected
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
