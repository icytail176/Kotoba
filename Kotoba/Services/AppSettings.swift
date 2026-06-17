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
    nonisolated static let selectedWordBookIDKey = "settings.selectedWordBookID"
    nonisolated static let lmStudioEnabledKey = "settings.lmStudio.enabled"
    nonisolated static let lmStudioBaseURLKey = "settings.lmStudio.baseURL"
    nonisolated static let lmStudioModelKey = "settings.lmStudio.model"
    nonisolated static let lmStudioTimeoutKey = "settings.lmStudio.timeout"
    nonisolated static let lmStudioBatchSizeKey = "settings.lmStudio.batchSize"
    nonisolated static let autoGenerateConjugationsKey = "settings.lmStudio.autoGenerateConjugations"

    nonisolated static let defaultDailyNewWordLimit = 20
    nonisolated static let minimumDailyNewWordLimit = 1
    nonisolated static let maximumDailyNewWordLimit = 100

    nonisolated static let defaultJapaneseSpeechRate = 0.5
    nonisolated static let minimumJapaneseSpeechRate = 0.35
    nonisolated static let maximumJapaneseSpeechRate = 0.65

    nonisolated static let defaultAutoSpeakWord = true
    nonisolated static let defaultAutoSpeakExample = false
    nonisolated static let defaultRandomizeStudyQueue = false

    nonisolated static let maximumReviewIntervalDays = 60

    nonisolated static let defaultLMStudioEnabled = false
    nonisolated static let defaultLMStudioBaseURL = "http://127.0.0.1:1234/v1"
    nonisolated static let defaultLMStudioModel = "local-model"
    nonisolated static let defaultLMStudioTimeout = 30.0
    nonisolated static let minimumLMStudioTimeout = 5.0
    nonisolated static let maximumLMStudioTimeout = 120.0
    nonisolated static let defaultLMStudioBatchSize = 8
    nonisolated static let minimumLMStudioBatchSize = 1
    nonisolated static let maximumLMStudioBatchSize = 50
    nonisolated static let defaultAutoGenerateConjugations = false

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

    nonisolated static func clampedLMStudioTimeout(_ value: Double) -> Double {
        min(max(value, minimumLMStudioTimeout), maximumLMStudioTimeout)
    }

    nonisolated static func clampedLMStudioBatchSize(_ value: Int) -> Int {
        min(max(value, minimumLMStudioBatchSize), maximumLMStudioBatchSize)
    }
}
