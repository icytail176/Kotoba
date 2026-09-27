//
//  AppSettings.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import Foundation

enum AppSettings {
    nonisolated static let studyGroupNewWordCountKey = "settings.studyGroupNewWordCount"
    nonisolated static let reviewGroupWordCountKey = "settings.reviewGroupWordCount"
    nonisolated static let selectedWordBookIDKey = "settings.selectedWordBookID"
    nonisolated static let builtInWordBookSeedVersionKey = "internal.builtInWordBookSeedVersion"
    nonisolated static let legacyCacheCleanupVersionKey = "internal.legacyCacheCleanupVersion"

    nonisolated static let defaultStudyGroupNewWordCount = 10
    nonisolated static let minimumStudyGroupNewWordCount = 1
    nonisolated static let maximumStudyGroupNewWordCount = 100
    nonisolated static let defaultReviewGroupWordCount = 20
    nonisolated static let minimumReviewGroupWordCount = 1
    nonisolated static let maximumReviewGroupWordCount = 200
    nonisolated static let defaultRandomizeStudyQueue = true
    nonisolated static let maximumReviewIntervalDays = 60

    nonisolated static func clampedStudyGroupNewWordCount(_ value: Int) -> Int {
        min(max(value, minimumStudyGroupNewWordCount), maximumStudyGroupNewWordCount)
    }

    nonisolated static func clampedReviewGroupWordCount(_ value: Int) -> Int {
        min(max(value, minimumReviewGroupWordCount), maximumReviewGroupWordCount)
    }
}
