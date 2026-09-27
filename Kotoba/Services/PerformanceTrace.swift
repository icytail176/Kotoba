//
//  PerformanceTrace.swift
//  Kotoba
//

import Foundation
import os

enum PerformanceTrace {
    #if DEBUG
    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.fumi.Kotoba",
        category: "Performance"
    )
    #endif

    nonisolated static func measure<T>(
        _ name: String,
        operation: () throws -> T
    ) rethrows -> T {
        #if DEBUG
        let start = ContinuousClock.now
        defer {
            record(name, elapsed: start.duration(to: .now))
        }
        #endif

        return try operation()
    }

    nonisolated static func record(_ name: String, elapsed: Duration) {
        #if DEBUG
        logger.notice("\(name, privacy: .public) completed in \(String(describing: elapsed), privacy: .public)")
        #endif
    }

    nonisolated static func event(_ name: String, _ message: String) {
        #if DEBUG
        logger.notice("\(name, privacy: .public): \(message, privacy: .public)")
        #endif
    }

    nonisolated static func fetch(_ name: String, count: Int) {
        event(name, "fetch count=\(count)")
    }

    nonisolated static func tableRender(_ name: String, rowCount: Int) {
        event(name, "rendered rows=\(rowCount)")
    }
}
