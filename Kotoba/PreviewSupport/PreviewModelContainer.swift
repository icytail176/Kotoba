//
//  PreviewModelContainer.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import Foundation
import SwiftData

enum PreviewModelContainer {
    @MainActor
    static func make(seedSampleWords: Bool = true) -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)

        do {
            let container = try ModelContainer(
                for: KotobaSchema.schema,
                configurations: [configuration]
            )

            if seedSampleWords {
                insertSampleWordsIfNeeded(in: container.mainContext)
            }

            return container
        } catch {
            fatalError("Failed to create preview model container: \(error)")
        }
    }

    @MainActor
    private static func insertSampleWordsIfNeeded(in context: ModelContext) {
        var descriptor = FetchDescriptor<VocabularyWord>()
        descriptor.fetchLimit = 1

        do {
            let existingWords = try context.fetch(descriptor)
            guard existingWords.isEmpty else {
                return
            }

            let referenceDate = Date(timeIntervalSinceReferenceDate: 0)
            for word in SampleVocabularyWords.makeWords(referenceDate: referenceDate) {
                context.insert(word)
            }

            try context.save()
        } catch {
            assertionFailure("Failed to seed preview sample words: \(error)")
        }
    }
}
