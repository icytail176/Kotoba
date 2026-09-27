//
//  KotobaStore.swift
//  Kotoba
//

import Foundation
import CoreData
import SwiftData

enum KotobaStoreError: LocalizedError {
    case backupFailed(Error)
    case openFailed(Error)

    var errorDescription: String? {
        switch self {
        case .backupFailed(let error):
            return "升级前备份失败：\(error.localizedDescription)"
        case .openFailed(let error):
            return "无法升级 Kotoba 学习数据库：\(error.localizedDescription)"
        }
    }
}

@MainActor
enum KotobaStore {
    private static let migrationBackupMarker = "Kotoba.didBackUpStoreBeforeSchemaV3"
    private static let storeOverrideEnvironmentKey = "KOTOBA_STORE_URL_OVERRIDE"

    static var defaultConfiguration: ModelConfiguration {
        ModelConfiguration(
            schema: KotobaSchema.schema,
            url: defaultStoreURL,
            cloudKitDatabase: .none
        )
    }

    static var defaultStoreURL: URL {
        if let override = ProcessInfo.processInfo.environment[storeOverrideEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return URL(fileURLWithPath: override)
        }

        return URL.applicationSupportDirectory
            .appendingPathComponent("Kotoba", isDirectory: true)
            .appendingPathComponent("Kotoba.store", isDirectory: false)
    }

    static var legacyDefaultStoreURL: URL {
        ModelConfiguration(schema: KotobaSchema.schema).url
    }

    static var backupRootURL: URL {
        backupRootURL(for: defaultStoreURL)
    }

    static func makeDefaultContainer() throws -> ModelContainer {
        let configuration = defaultConfiguration
        let defaults = UserDefaults.standard

        do {
            try FileManager.default.createDirectory(
                at: configuration.url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try copyLegacyStoreFamilyIfNeeded(
                from: legacyDefaultStoreURL,
                to: configuration.url
            )
        } catch {
            throw KotobaStoreError.backupFailed(error)
        }

        if !defaults.bool(forKey: migrationBackupMarker) {
            do {
                try backUpStoreFamilyIfPresent(at: configuration.url)
            } catch {
                throw KotobaStoreError.backupFailed(error)
            }
        }

        do {
            let container = try ModelContainer(
                for: KotobaSchema.schema,
                migrationPlan: KotobaMigrationPlan.self,
                configurations: [configuration]
            )
            defaults.set(true, forKey: migrationBackupMarker)
            return container
        } catch {
            throw KotobaStoreError.openFailed(error)
        }
    }

    static func makeContainer(at storeURL: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: KotobaSchema.schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: KotobaSchema.schema,
            migrationPlan: KotobaMigrationPlan.self,
            configurations: [configuration]
        )
    }

    private static func backupRootURL(for storeURL: URL) -> URL {
        storeURL.deletingLastPathComponent()
            .appendingPathComponent("Database Backups", isDirectory: true)
    }

    static func isLegacyKotobaStore(at storeURL: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: storeURL.path),
              let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(
                type: .sqlite,
                at: storeURL
              ),
              let hashes = metadata[NSStoreModelVersionHashesKey] as? [String: Any] else {
            return false
        }

        let requiredEntities: Set<String> = [
            "WordBook",
            "VocabularyWord",
            "LearningProgress",
            "ReviewLog"
        ]
        return requiredEntities.isSubset(of: Set(hashes.keys))
    }

    static func copyLegacyStoreFamilyIfNeeded(from sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: destinationURL.path),
              sourceURL.standardizedFileURL != destinationURL.standardizedFileURL,
              isLegacyKotobaStore(at: sourceURL) else {
            return
        }

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let sources = try storeFamily(at: sourceURL)
        var created: [URL] = []
        do {
            for source in sources {
                let suffix = source.lastPathComponent.dropFirst(sourceURL.lastPathComponent.count)
                let target = destinationURL.deletingLastPathComponent()
                    .appendingPathComponent(destinationURL.lastPathComponent + suffix)
                try fileManager.copyItem(at: source, to: target)
                created.append(target)
            }
        } catch {
            for item in created {
                try? fileManager.removeItem(at: item)
            }
            throw error
        }
    }

    @discardableResult
    static func backUpStoreFamilyIfPresent(
        at storeURL: URL,
        backupRootOverride: URL? = nil,
        copyItem: ((URL, URL) throws -> Void)? = nil
    ) throws -> URL? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: storeURL.path) else {
            return nil
        }

        let parentURL = storeURL.deletingLastPathComponent()
        let backupRoot = backupRootOverride ?? backupRootURL(for: storeURL)
        try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let destination = backupRoot.appendingPathComponent(
            "schema-before-v3-\(formatter.string(from: Date()))-\(UUID().uuidString)",
            isDirectory: true
        )

        var coordinationError: NSError?
        var copyError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: parentURL, options: .withoutChanges, error: &coordinationError) { coordinatedParent in
            do {
                try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
                let family = try storeFamily(
                    at: coordinatedParent.appendingPathComponent(storeURL.lastPathComponent)
                )

                for source in family {
                    let target = destination.appendingPathComponent(source.lastPathComponent)
                    if let copyItem {
                        try copyItem(source, target)
                    } else {
                        try fileManager.copyItem(at: source, to: target)
                    }
                }
            } catch {
                copyError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let copyError {
            throw copyError
        }
        return destination
    }

    private static func storeFamily(at storeURL: URL) throws -> [URL] {
        let storeName = storeURL.lastPathComponent
        return try FileManager.default.contentsOfDirectory(
            at: storeURL.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        ).filter { item in
            item.lastPathComponent == storeName
                || item.lastPathComponent.hasPrefix("\(storeName)-")
                || item.lastPathComponent.hasPrefix("\(storeName).")
                || item.lastPathComponent.hasPrefix("\(storeName)_")
        }
    }
}
