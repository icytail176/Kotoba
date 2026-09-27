//
//  ModelContainerTestSupport.swift
//  KotobaTests
//
//  Created by Codex on 2026/6/16.
//

import SwiftData
import XCTest
@testable import Kotoba

@MainActor
func makeInMemoryTestContainer(file: StaticString = #filePath, line: UInt = #line) throws -> ModelContainer {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)

    do {
        return try ModelContainer(
            for: KotobaSchema.schema,
            migrationPlan: KotobaMigrationPlan.self,
            configurations: [configuration]
        )
    } catch {
        XCTFail("Failed to create in-memory ModelContainer: \(error)", file: file, line: line)
        throw error
    }
}
