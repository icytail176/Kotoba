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

struct ReviewForecastBucket: Identifiable, Equatable, Sendable {
    var id: Int { dayOffset }

    let dayOffset: Int
    let day: Date
    let reviewCount: Int
}

struct HomeDashboardSnapshot: Equatable {
    let wordBookID: UUID?
    let wordBookName: String
    let wordBookDescription: String
    let totalWordCount: Int
    let remainingNewWordCount: Int
    let dueReviewCount: Int
    let reviewingWordCount: Int
    let masteredWordCount: Int
    let reviewForecast: [ReviewForecastBucket]
    let hasWordBooks: Bool
    let isBuiltInWordBook: Bool
    let example: HomeExample?
}

@MainActor
struct HomeDashboardService {
    func makeSnapshot(
        in context: ModelContext,
        selectedIDString: String?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> (snapshot: HomeDashboardSnapshot, resolvedWordBook: WordBook?, wordBooks: [WordBook]) {
        try PerformanceTrace.measure("Home dashboard load") {
            let wordBookService = WordBookService()
            let books = try wordBookService.fetchWordBooks(in: context)
            let selectedID = selectedIDString.flatMap(UUID.init(uuidString:))
            guard let selectedBook = books.first(where: { $0.id == selectedID }) ?? books.first else {
                return (
                    HomeDashboardSnapshot(
                        wordBookID: nil,
                        wordBookName: "",
                        wordBookDescription: "",
                        totalWordCount: 0,
                        remainingNewWordCount: 0,
                        dueReviewCount: 0,
                        reviewingWordCount: 0,
                        masteredWordCount: 0,
                        reviewForecast: Self.reviewForecast(words: [], now: now, calendar: calendar),
                        hasWordBooks: !books.isEmpty,
                        isBuiltInWordBook: false,
                        example: nil
                    ),
                    nil,
                    books
                )
            }

            let selectedBookID = selectedBook.id
            var descriptor = FetchDescriptor<VocabularyWord>(predicate: #Predicate { word in
                word.wordBook?.id == selectedBookID && !word.isArchived
            })
            descriptor.includePendingChanges = true
            let words = try context.fetch(descriptor)
            let remainingNewWordCount = words.filter { $0.progress?.state == .new }.count
            let dueReviewCount = words.filter { word in
                guard let progress = word.progress else {
                    return false
                }

                return StudyDuePolicy.isDue(progress: progress, now: now, calendar: calendar)
            }.count
            let reviewingWordCount = words.filter {
                LearningStatePresentation.isReviewing($0.progress?.state)
            }.count
            let masteredWordCount = words.filter { $0.progress?.state == .suspended }.count

            return (
                HomeDashboardSnapshot(
                    wordBookID: selectedBook.id,
                    wordBookName: selectedBook.name,
                    wordBookDescription: selectedBook.bookDescription,
                    totalWordCount: words.count,
                    remainingNewWordCount: remainingNewWordCount,
                    dueReviewCount: dueReviewCount,
                    reviewingWordCount: reviewingWordCount,
                    masteredWordCount: masteredWordCount,
                    reviewForecast: Self.reviewForecast(words: words, now: now, calendar: calendar),
                    hasWordBooks: true,
                    isBuiltInWordBook: selectedBook.isBuiltIn,
                    example: randomExample(from: words)
                ),
                selectedBook,
                books
            )
        }
    }

    nonisolated static func reviewForecast(
        words: [VocabularyWord],
        now: Date,
        calendar: Calendar
    ) -> [ReviewForecastBucket] {
        let today = calendar.startOfDay(for: now)
        var counts = Array(repeating: 0, count: 7)

        for word in words where !word.isArchived {
            guard let progress = word.progress,
                  progress.state == .learning
                    || progress.state == .relearning
                    || progress.state == .review else {
                continue
            }

            let dueDay = calendar.startOfDay(for: progress.dueAt)
            let offset = max(0, calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0)
            guard counts.indices.contains(offset) else { continue }
            counts[offset] += 1
        }

        return counts.indices.compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return ReviewForecastBucket(dayOffset: offset, day: day, reviewCount: counts[offset])
        }
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

}
