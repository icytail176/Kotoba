//
//  KotobaBackupImporter.swift
//  Kotoba
//

import Foundation
import SwiftData

nonisolated enum KotobaBackupImportError: LocalizedError, Equatable, Sendable {
    case alreadyInProgress

    var errorDescription: String? {
        switch self {
        case .alreadyInProgress:
            return "已有备份导入正在进行，请等待完成。"
        }
    }
}

nonisolated protocol KotobaBackupImporting: Sendable {
    func importBackup(
        from data: Data,
        strategy: KotobaBackupImportStrategy
    ) async throws -> KotobaBackupImportResult
}

nonisolated struct KotobaBackupImportProfile: Sendable {
    let result: KotobaBackupImportResult
    let phaseMilliseconds: [String: Double]
    let totalMilliseconds: Double
}

/// Owns the SwiftData context used by one restore operation. Only Sendable
/// backup DTOs and result values cross this actor boundary.
@ModelActor
actor KotobaBackupImportStore {
    func importBackup(
        from data: Data,
        strategy: KotobaBackupImportStrategy,
        beforeImport: (@Sendable () async throws -> Void)? = nil,
        beforeSave: (@Sendable () throws -> Void)? = nil
    ) async throws -> KotobaBackupImportResult {
        try Task.checkCancellation()
        try await beforeImport?()
        try Task.checkCancellation()

        let service = KotobaBackupService(beforeSave: beforeSave)
        return try service.importBackup(from: data, strategy: strategy, in: modelContext)
    }

    func profileImportBackup(
        from data: Data,
        strategy: KotobaBackupImportStrategy
    ) throws -> KotobaBackupImportProfile {
        var phases: [String: Double] = [:]
        let service = KotobaBackupService { phase, elapsed in
            phases[phase, default: 0] += Self.milliseconds(elapsed)
        }
        let start = ContinuousClock.now
        let result = try service.importBackup(from: data, strategy: strategy, in: modelContext)
        return KotobaBackupImportProfile(
            result: result,
            phaseMilliseconds: phases,
            totalMilliseconds: Self.milliseconds(start.duration(to: .now))
        )
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}

/// The coordinator is intentionally separate from the ModelActor. While the
/// store actor is busy applying a large restore, this actor can still reject a
/// second request instead of queueing another mutation against the same store.
actor KotobaBackupImportCoordinator: KotobaBackupImporting {
    private let store: KotobaBackupImportStore
    private let beforeImport: (@Sendable () async throws -> Void)?
    private let beforeSave: (@Sendable () throws -> Void)?
    private var isImporting = false

    init(
        modelContainer: ModelContainer,
        beforeImport: (@Sendable () async throws -> Void)? = nil,
        beforeSave: (@Sendable () throws -> Void)? = nil
    ) {
        store = KotobaBackupImportStore(modelContainer: modelContainer)
        self.beforeImport = beforeImport
        self.beforeSave = beforeSave
    }

    func importBackup(
        from data: Data,
        strategy: KotobaBackupImportStrategy
    ) async throws -> KotobaBackupImportResult {
        guard !isImporting else {
            throw KotobaBackupImportError.alreadyInProgress
        }

        isImporting = true
        defer { isImporting = false }

        return try await store.importBackup(
            from: data,
            strategy: strategy,
            beforeImport: beforeImport,
            beforeSave: beforeSave
        )
    }

    func hasImportInProgress() -> Bool {
        isImporting
    }

    func profileImportBackup(
        from data: Data,
        strategy: KotobaBackupImportStrategy
    ) async throws -> KotobaBackupImportProfile {
        guard !isImporting else {
            throw KotobaBackupImportError.alreadyInProgress
        }

        isImporting = true
        defer { isImporting = false }
        return try await store.profileImportBackup(from: data, strategy: strategy)
    }
}
