//
//  BuiltInWordBookInitializationCoordinator.swift
//  Kotoba
//

import Foundation
import SwiftData

/// Shares one built-in seed/repair operation between every caller in this
/// process. SwiftData's main context is MainActor-bound, so the task also
/// serializes all mutations of the store.
@MainActor
final class BuiltInWordBookInitializationCoordinator {
    typealias ServiceFactory = @MainActor () -> BuiltInWordBookService

    static let shared = BuiltInWordBookInitializationCoordinator()

    private let serviceFactory: ServiceFactory
    private var inFlight: Task<[BuiltInWordBookLoadResult], Error>?

    init(serviceFactory: @escaping ServiceFactory = { BuiltInWordBookService() }) {
        self.serviceFactory = serviceFactory
    }

    func loadIfNeeded(
        in context: ModelContext,
        now: Date = Date()
    ) async throws -> [BuiltInWordBookLoadResult] {
        if let inFlight {
            return try await inFlight.value
        }

        let service = serviceFactory()
        let task = Task { @MainActor in
            try service.loadIfNeeded(in: context, now: now)
        }
        inFlight = task

        do {
            let result = try await task.value
            inFlight = nil
            return result
        } catch {
            inFlight = nil
            throw error
        }
    }
}
