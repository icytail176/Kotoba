//
//  StudyStatisticsService.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import Foundation
import SwiftData

@MainActor
struct StudyStatisticsService {
    func makeInput(in context: ModelContext) throws -> StudyStatisticsInput {
        let logs = try context.fetch(FetchDescriptor<ReviewLog>(sortBy: [
            SortDescriptor(\.reviewedAt, order: .forward)
        ]))
        let words = try context.fetch(FetchDescriptor<VocabularyWord>())

        return StudyStatisticsInput(
            logs: logs.map { log in
                StudyLogSnapshot(
                    id: log.id,
                    wordID: log.word?.id,
                    reviewedAt: log.reviewedAt,
                    rating: log.rating,
                    previousState: log.previousState,
                    nextState: log.nextState
                )
            },
            words: words.map { word in
                StudyWordSnapshot(
                    id: word.id,
                    expression: word.japanese,
                    reading: word.kana,
                    meaningChinese: word.chineseMeaning,
                    jlptLevel: word.jlptLevel,
                    isArchived: word.isArchived
                )
            }
        )
    }
}
