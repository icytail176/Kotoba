//
//  KotobaSchema.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import SwiftData

enum KotobaSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static let models: [any PersistentModel.Type] = [
        WordBook.self,
        VocabularyWord.self,
        LearningProgress.self,
        ReviewLog.self
    ]

    static var schema: Schema { Schema(versionedSchema: Self.self) }
}

enum KotobaMigrationPlan: SchemaMigrationPlan {
    static let schemas: [any VersionedSchema.Type] = [
        KotobaSchemaV1.self,
        KotobaSchemaV2.self,
        KotobaSchemaV3.self
    ]

    static let stages: [MigrationStage] = [
        .lightweight(fromVersion: KotobaSchemaV1.self, toVersion: KotobaSchemaV2.self),
        .lightweight(fromVersion: KotobaSchemaV2.self, toVersion: KotobaSchemaV3.self)
    ]
}

enum KotobaSchema {
    static let models = KotobaSchemaV3.models

    static var schema: Schema {
        KotobaSchemaV3.schema
    }
}
