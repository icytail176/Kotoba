//
//  DataManagementService.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import Foundation
import SwiftData

@MainActor
struct DataManagementService {
    func clearAllData(in context: ModelContext) throws {
        do {
            let wordBooks = try context.fetch(FetchDescriptor<WordBook>())
            let words = try context.fetch(FetchDescriptor<VocabularyWord>())
            let progressItems = try context.fetch(FetchDescriptor<LearningProgress>())
            let logs = try context.fetch(FetchDescriptor<ReviewLog>())
            let conjugationRecords = try context.fetch(FetchDescriptor<ConjugationRecord>())
            let orphanProgress = progressItems.filter { $0.word == nil }
            let orphanLogs = logs.filter { $0.word == nil }

            for record in conjugationRecords {
                context.delete(record)
            }

            for wordBook in wordBooks {
                context.delete(wordBook)
            }

            for word in words {
                context.delete(word)
            }

            for progress in orphanProgress {
                context.delete(progress)
            }

            for log in orphanLogs {
                context.delete(log)
            }

            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
