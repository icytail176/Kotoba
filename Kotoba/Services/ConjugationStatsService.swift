//
//  ConjugationStatsService.swift
//  Kotoba
//
//  Created by Codex on 2026/6/17.
//

import Foundation
import SwiftData

struct ConjugationStats: Equatable {
    let possibleCount: Int
    let validCount: Int
    let localRuleCount: Int
    let needsReviewCount: Int
    let invalidCount: Int
    let pendingCount: Int
}

@MainActor
struct ConjugationStatsService {
    private let tokenizer = PartOfSpeechTokenizer()
    private let cacheService = ConjugationCacheService()

    func stats(for wordBook: WordBook, in context: ModelContext) throws -> ConjugationStats {
        let words = wordBook.words.filter { !$0.isArchived }
        let possibleWords = words.filter(mayNeedConjugation)
        let wordIDs = Set(possibleWords.map(\.id))
        let records = try context.fetch(FetchDescriptor<ConjugationRecord>())
            .filter { wordIDs.contains($0.wordID) }

        let validWordIDs = Set(records.filter {
            $0.validationStatus == .valid && !$0.markedIncorrect
        }.map(\.wordID))

        return ConjugationStats(
            possibleCount: possibleWords.count,
            validCount: validWordIDs.count,
            localRuleCount: records.filter { $0.source == .localRule && $0.validationStatus == .valid }.count,
            needsReviewCount: records.filter { $0.validationStatus == .needsReview }.count,
            invalidCount: records.filter { $0.validationStatus == .invalid || $0.markedIncorrect }.count,
            pendingCount: max(0, possibleWords.count - validWordIDs.count)
        )
    }

    func fillLocalRules(for wordBook: WordBook, in context: ModelContext) throws {
        for word in wordBook.words where !word.isArchived && mayNeedConjugation(word) {
            _ = try cacheService.ensureLocalRecord(for: word, in: context)
        }
    }

    private func mayNeedConjugation(_ word: VocabularyWord) -> Bool {
        let tokens = Set(tokenizer.tokens(from: word.partOfSpeech))
        return tokens.contains("一段动词")
            || tokens.contains("一段動詞")
            || tokens.contains("五段动词")
            || tokens.contains("五段動詞")
            || tokens.contains("サ变动词")
            || tokens.contains("サ変動詞")
            || tokens.contains("する动词")
            || tokens.contains("カ变动词")
            || tokens.contains("カ変動詞")
            || tokens.contains("い形容词")
            || tokens.contains("い形容詞")
            || tokens.contains("な形容词")
            || tokens.contains("な形容詞")
            || tokens.contains("动词")
            || tokens.contains("動詞")
            || tokens.contains("形容词")
            || tokens.contains("形容詞")
    }
}
