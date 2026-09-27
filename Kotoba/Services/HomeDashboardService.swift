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
    let remainingNewWordCount: Int
    let dueReviewCount: Int
    let masteredWordCount: Int
    let hasWordBooks: Bool
    let example: HomeExample?
}

@MainActor
struct HomeDashboardService {
    func makeSnapshot(
        in context: ModelContext,
        selectedIDString: String?,
        now: Date = Date()
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
                        masteredWordCount: 0,
                        hasWordBooks: !books.isEmpty,
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

                return StudyDuePolicy.isDue(progress: progress, now: now)
            }.count
            let masteredWordCount = words.filter { $0.progress?.state == .review }.count

            return (
                HomeDashboardSnapshot(
                    wordBookID: selectedBook.id,
                    wordBookName: selectedBook.name,
                    wordBookDescription: selectedBook.bookDescription,
                    totalWordCount: words.count,
                    remainingNewWordCount: remainingNewWordCount,
                    dueReviewCount: dueReviewCount,
                    masteredWordCount: masteredWordCount,
                    hasWordBooks: true,
                    example: randomExample(from: words)
                ),
                selectedBook,
                books
            )
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
