//
//  HomeSearchService.swift
//  Kotoba
//
//  Created by Codex on 2026/6/17.
//

import Foundation
import SwiftData

struct HomeSearchSuggestion: Identifiable, Equatable {
    let id: UUID
    let wordID: UUID
    let wordBookID: UUID?
    let expression: String
    let reading: String
    let meaningChinese: String
    let wordBookName: String
}

@MainActor
struct HomeSearchService {
    private let partOfSpeechTokenizer = PartOfSpeechTokenizer()

    func suggestions(
        in context: ModelContext,
        query: String,
        currentWordBookID: UUID?,
        limit: Int = 8
    ) throws -> [HomeSearchSuggestion] {
        try PerformanceTrace.measure("Home search") {
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedQuery.isEmpty else {
                return []
            }

            var textDescriptor = FetchDescriptor<VocabularyWord>(predicate: #Predicate { word in
                !word.isArchived
                    && (word.japanese.contains(trimmedQuery)
                        || word.kana.contains(trimmedQuery)
                        || word.chineseMeaning.contains(trimmedQuery))
            })
            let candidateLimit = max(40, limit * 5)
            textDescriptor.fetchLimit = candidateLimit

            var partOfSpeechDescriptor = FetchDescriptor<VocabularyWord>(predicate: #Predicate { word in
                !word.isArchived && word.partOfSpeech.contains(trimmedQuery)
            })
            partOfSpeechDescriptor.fetchLimit = candidateLimit

            let textWords = try context.fetch(textDescriptor)
            let partOfSpeechWords = try context.fetch(partOfSpeechDescriptor)
            PerformanceTrace.fetch("Home search text fetch", count: textWords.count)
            PerformanceTrace.fetch("Home search partOfSpeech fetch", count: partOfSpeechWords.count)
            let indexedWords = uniqueWords(textWords + partOfSpeechWords)
            let words: [VocabularyWord]
            if indexedWords.isEmpty {
                var fallbackDescriptor = FetchDescriptor<VocabularyWord>(
                    predicate: #Predicate { word in
                        !word.isArchived
                    },
                    sortBy: [
                        SortDescriptor(\.japanese, order: .forward),
                        SortDescriptor(\.kana, order: .forward)
                    ]
                )
                fallbackDescriptor.fetchLimit = candidateLimit * 3
                // Tags are stored as an array and are not reliably indexed by SwiftData here,
                // so fallback tag search intentionally scans only a bounded candidate window.
                let tagFallbackWords = try context.fetch(fallbackDescriptor)
                    .filter { word in
                        word.tags.contains(where: { $0.localizedCaseInsensitiveContains(trimmedQuery) })
                    }
                    .prefix(candidateLimit)
                PerformanceTrace.fetch("Home search bounded tag fallback fetch", count: tagFallbackWords.count)
                words = uniqueWords(Array(tagFallbackWords))
            } else {
                words = indexedWords
            }

            return words
                .compactMap { suggestionCandidate(for: $0, query: trimmedQuery) }
                .sorted { lhs, rhs in
                    if lhs.rank != rhs.rank {
                        return lhs.rank < rhs.rank
                    }

                    let lhsIsCurrent = lhs.word.wordBook?.id == currentWordBookID
                    let rhsIsCurrent = rhs.word.wordBook?.id == currentWordBookID
                    if lhsIsCurrent != rhsIsCurrent {
                        return lhsIsCurrent
                    }

                    return lhs.word.japanese.localizedStandardCompare(rhs.word.japanese) == .orderedAscending
                }
                .prefix(max(1, limit))
                .map { candidate in
                    HomeSearchSuggestion(
                        id: candidate.word.id,
                        wordID: candidate.word.id,
                        wordBookID: candidate.word.wordBook?.id,
                        expression: candidate.word.japanese,
                        reading: candidate.word.kana,
                        meaningChinese: candidate.word.chineseMeaning,
                        wordBookName: candidate.word.wordBook?.name ?? "未归属词书"
                    )
                }
        }
    }

    func fetchWord(id: UUID, in context: ModelContext) throws -> VocabularyWord? {
        var descriptor = FetchDescriptor<VocabularyWord>(predicate: #Predicate { word in
            word.id == id
        })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func suggestionCandidate(for word: VocabularyWord, query: String) -> (word: VocabularyWord, rank: Int)? {
        if word.japanese == query {
            return (word, 0)
        }

        if word.kana == query {
            return (word, 1)
        }

        if word.japanese.hasPrefix(query) {
            return (word, 2)
        }

        if word.kana.hasPrefix(query) {
            return (word, 3)
        }

        if word.chineseMeaning == query {
            return (word, 4)
        }

        if word.chineseMeaning.localizedCaseInsensitiveContains(query) {
            return (word, 5)
        }

        if word.tags.contains(where: { $0.localizedCaseInsensitiveContains(query) }) {
            return (word, 6)
        }

        if partOfSpeechTokenizer.tokens(from: word.partOfSpeech).contains(where: {
            $0.localizedCaseInsensitiveContains(query)
        }) {
            return (word, 6)
        }

        if word.japanese.localizedCaseInsensitiveContains(query)
            || word.kana.localizedCaseInsensitiveContains(query) {
            return (word, 7)
        }

        return nil
    }

    private func uniqueWords(_ words: [VocabularyWord]) -> [VocabularyWord] {
        var seenIDs = Set<UUID>()
        return words.filter { seenIDs.insert($0.id).inserted }
    }
}
