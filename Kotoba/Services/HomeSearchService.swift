//
//  HomeSearchService.swift
//  Kotoba
//
//  Created by Codex on 2026/6/17.
//

import Foundation
import SwiftData

enum HomeSearchScope: String, CaseIterable, Identifiable {
    case currentWordBook
    case allWordBooks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .currentWordBook:
            return "当前词书"
        case .allWordBooks:
            return "全部词书"
        }
    }
}

struct HomeSearchSuggestion: Identifiable, Equatable {
    let id: UUID
    let wordID: UUID
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
        scope: HomeSearchScope,
        currentWordBookID: UUID?,
        limit: Int = 10
    ) throws -> [HomeSearchSuggestion] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return []
        }

        let words = try context.fetch(FetchDescriptor<VocabularyWord>())
            .filter { word in
                guard !word.isArchived else {
                    return false
                }

                switch scope {
                case .currentWordBook:
                    guard let currentWordBookID else {
                        return false
                    }
                    return word.wordBook?.id == currentWordBookID
                case .allWordBooks:
                    return true
                }
            }

        return words
            .compactMap { suggestionCandidate(for: $0, query: trimmedQuery) }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank {
                    return lhs.rank < rhs.rank
                }

                return lhs.word.japanese.localizedStandardCompare(rhs.word.japanese) == .orderedAscending
            }
            .prefix(max(1, limit))
            .map { candidate in
                HomeSearchSuggestion(
                    id: candidate.word.id,
                    wordID: candidate.word.id,
                    expression: candidate.word.japanese,
                    reading: candidate.word.kana,
                    meaningChinese: candidate.word.chineseMeaning,
                    wordBookName: candidate.word.wordBook?.name ?? "未归属词书"
                )
            }
    }

    func fetchWord(id: UUID, in context: ModelContext) throws -> VocabularyWord? {
        let words = try context.fetch(FetchDescriptor<VocabularyWord>())
        return words.first { $0.id == id }
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

        if word.chineseMeaning.localizedCaseInsensitiveContains(query) {
            return (word, 4)
        }

        if word.tags.contains(where: { $0.localizedCaseInsensitiveContains(query) }) {
            return (word, 5)
        }

        if partOfSpeechTokenizer.tokens(from: word.partOfSpeech).contains(where: {
            $0.localizedCaseInsensitiveContains(query)
        }) {
            return (word, 5)
        }

        if word.japanese.localizedCaseInsensitiveContains(query)
            || word.kana.localizedCaseInsensitiveContains(query) {
            return (word, 6)
        }

        return nil
    }
}
