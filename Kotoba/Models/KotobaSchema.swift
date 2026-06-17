//
//  KotobaSchema.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import SwiftData

enum KotobaSchema {
    static let models: [any PersistentModel.Type] = [
        WordBook.self,
        VocabularyWord.self,
        LearningProgress.self,
        ReviewLog.self,
        ConjugationRecord.self
    ]

    static var schema: Schema {
        Schema(models)
    }
}
