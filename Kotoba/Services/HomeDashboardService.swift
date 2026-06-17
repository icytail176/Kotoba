//
//  HomeDashboardService.swift
//  Kotoba
//
//  Created by Codex on 2026/6/17.
//

import Foundation
import SwiftData

struct HomeExample: Equatable {
    let wordID: UUID
    let expression: String
    let japanese: String
    let chinese: String
}

struct HomeDashboardSnapshot: Equatable {
    let wordBookID: UUID?
    let wordBookName: String
    let wordBookDescription: String
    let totalWordCount: Int
    let availableNewWordCount: Int
    let dueReviewCount: Int
    let masteredWordCount: Int
    let hasWordBooks: Bool
    let example: HomeExample?
}

@MainActor
struct HomeDashboardService {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func makeSnapshot(
        in context: ModelContext,
        selectedIDString: String?,
        dailyNewWordLimit: Int,
        now: Date = Date()
    ) throws -> (snapshot: HomeDashboardSnapshot, resolvedWordBook: WordBook?) {
        let wordBookService = WordBookService()
        let books = try wordBookService.fetchWordBooks(in: context)
        guard let selectedBook = try wordBookService.resolveSelectedWordBook(
            in: context,
            selectedIDString: selectedIDString
        ) else {
            return (
                HomeDashboardSnapshot(
                    wordBookID: nil,
                    wordBookName: "",
                    wordBookDescription: "",
                    totalWordCount: 0,
                    availableNewWordCount: 0,
                    dueReviewCount: 0,
                    masteredWordCount: 0,
                    hasWordBooks: !books.isEmpty,
                    example: nil
                ),
                nil
            )
        }

        let words = selectedBook.words.filter { !$0.isArchived }
        let introducedToday = countNewWordsIntroducedToday(from: words, now: now)
        let availableNewWordCount = min(
            max(0, dailyNewWordLimit - introducedToday),
            words.filter { $0.progress?.state == .new }.count
        )
        let dueReviewCount = words.filter { word in
            guard let progress = word.progress else {
                return false
            }

            return progress.state != .new
                && progress.state != .suspended
                && progress.dueAt <= now
        }.count
        let masteredWordCount = words.filter { $0.progress?.state == .review }.count

        return (
            HomeDashboardSnapshot(
                wordBookID: selectedBook.id,
                wordBookName: selectedBook.name,
                wordBookDescription: selectedBook.bookDescription,
                totalWordCount: words.count,
                availableNewWordCount: availableNewWordCount,
                dueReviewCount: dueReviewCount,
                masteredWordCount: masteredWordCount,
                hasWordBooks: true,
                example: randomExample(from: words)
            ),
            selectedBook
        )
    }

    func randomExample(from words: [VocabularyWord]) -> HomeExample? {
        let completeWords = words.filter { word in
            !word.exampleJapanese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !word.exampleChinese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let preferredWords = completeWords.filter { word in
            word.exampleJapanese.contains(word.japanese)
        }
        let candidates = preferredWords.isEmpty ? completeWords : preferredWords

        guard let word = candidates.randomElement() else {
            return nil
        }

        return HomeExample(
            wordID: word.id,
            expression: word.japanese,
            japanese: word.exampleJapanese,
            chinese: word.exampleChinese
        )
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
}
