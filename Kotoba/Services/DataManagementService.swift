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
            let words = try context.fetch(FetchDescriptor<VocabularyWord>())
            for word in words {
                context.delete(word)
            }

            try context.save()

            let remainingProgress = try context.fetch(FetchDescriptor<LearningProgress>())
            let remainingLogs = try context.fetch(FetchDescriptor<ReviewLog>())

            for progress in remainingProgress {
                context.delete(progress)
            }

            for log in remainingLogs {
                context.delete(log)
            }

            if !remainingProgress.isEmpty || !remainingLogs.isEmpty {
                try context.save()
            }
        } catch {
            context.rollback()
            throw error
        }
    }
}
