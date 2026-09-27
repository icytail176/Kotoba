//
//  LegacyCacheCleanupService.swift
//  Kotoba
//
//  Removes only file caches created by features that no longer exist.
//

import Foundation
import OSLog

enum LegacyCacheCleanupService {
    private nonisolated static let currentVersion = 1

    nonisolated static func runIfNeeded() {
        let logger = Logger(subsystem: "com.fumi.Kotoba", category: "LegacyCacheCleanup")
        let userDefaults = UserDefaults.standard
        guard userDefaults.integer(forKey: AppSettings.legacyCacheCleanupVersionKey) < currentVersion else {
            return
        }

        let fileManager = FileManager.default
        var directories = [
            fileManager.temporaryDirectory.appendingPathComponent("KotobaVoiceSessions", isDirectory: true),
            fileManager.temporaryDirectory.appendingPathComponent("TempVoiceSessions", isDirectory: true)
        ]

        if let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            directories.append(
                applicationSupport
                    .appendingPathComponent("Kotoba", isDirectory: true)
                    .appendingPathComponent("DictionaryCache", isDirectory: true)
            )
        }

        for directory in directories where fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.removeItem(at: directory)
            } catch {
                logger.error("Unable to remove deprecated cache directory: \(directory.path, privacy: .private(mask: .hash)); \(error.localizedDescription, privacy: .public)")
            }
        }

        userDefaults.set(currentVersion, forKey: AppSettings.legacyCacheCleanupVersionKey)
    }
}
