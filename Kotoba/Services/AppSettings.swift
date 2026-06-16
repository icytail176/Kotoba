//
//  AppSettings.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import Foundation

enum AppSettings {
    nonisolated static let dailyNewWordLimitKey = "settings.dailyNewWordLimit"
    nonisolated static let japaneseSpeechRateKey = "settings.japaneseSpeechRate"
    nonisolated static let autoSpeakWordKey = "settings.autoSpeakWord"
    nonisolated static let autoSpeakExampleKey = "settings.autoSpeakExample"
    nonisolated static let randomizeStudyQueueKey = "settings.randomizeStudyQueue"

    nonisolated static let defaultDailyNewWordLimit = 20
    nonisolated static let minimumDailyNewWordLimit = 1
    nonisolated static let maximumDailyNewWordLimit = 100

    nonisolated static let defaultJapaneseSpeechRate = 0.5
    nonisolated static let minimumJapaneseSpeechRate = 0.35
    nonisolated static let maximumJapaneseSpeechRate = 0.65

    nonisolated static let defaultAutoSpeakWord = false
    nonisolated static let defaultAutoSpeakExample = false
    nonisolated static let defaultRandomizeStudyQueue = false

    nonisolated static let maximumReviewIntervalDays = 60

    nonisolated static func clampedDailyNewWordLimit(_ value: Int) -> Int {
        min(max(value, minimumDailyNewWordLimit), maximumDailyNewWordLimit)
    }

    nonisolated static func clampedJapaneseSpeechRate(_ value: Double) -> Double {
        min(max(value, minimumJapaneseSpeechRate), maximumJapaneseSpeechRate)
    }

    nonisolated static func clampedJapaneseSpeechRate(_ value: Float) -> Float {
        let minimumRate = Float(minimumJapaneseSpeechRate)
        let maximumRate = Float(maximumJapaneseSpeechRate)
        return min(max(value, minimumRate), maximumRate)
    }
}
