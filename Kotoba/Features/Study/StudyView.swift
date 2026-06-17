//
//  StudyView.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import SwiftData
import SwiftUI

struct StudyView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppSettings.dailyNewWordLimitKey) private var dailyNewWordLimit = AppSettings.defaultDailyNewWordLimit
    @AppStorage(AppSettings.japaneseSpeechRateKey) private var japaneseSpeechRate = AppSettings.defaultJapaneseSpeechRate
    @AppStorage(AppSettings.autoSpeakWordKey) private var autoSpeakWord = AppSettings.defaultAutoSpeakWord
    @AppStorage(AppSettings.autoSpeakExampleKey) private var autoSpeakExample = AppSettings.defaultAutoSpeakExample
    @AppStorage(AppSettings.randomizeStudyQueueKey) private var randomizeStudyQueue = AppSettings.defaultRandomizeStudyQueue
    @StateObject private var viewModel = StudySessionViewModel()
    let wordBookID: UUID?
    let mode: StudySession.Mode
    let completedTitle: String
    let completedMessage: String

    init(
        wordBookID: UUID? = nil,
        mode: StudySession.Mode = .mixed,
        completedTitle: String = "今日学习已完成",
        completedMessage: String = "当前没有到期复习，也没有需要加入队列的新词。"
    ) {
        self.wordBookID = wordBookID
        self.mode = mode
        self.completedTitle = completedTitle
        self.completedMessage = completedMessage
    }

    var body: some View {
        Group {
            if let summary = viewModel.summary {
                StudySummaryView(summary: summary)
            } else if let errorMessage = viewModel.errorMessage {
                EmptyStateView(
                    systemImage: "exclamationmark.triangle",
                    title: "学习队列加载失败",
                    message: errorMessage
                )
            } else if viewModel.isSpellingActive {
                SpellingView(
                    words: viewModel.spellingWords,
                    conjugationRecords: viewModel.spellingConjugationRecords,
                    autoSpeakAnswer: autoSpeakWord,
                    speechState: viewModel.speechState,
                    onSpeakAnswer: { text in
                        viewModel.speakSpellingAnswer(text)
                    },
                    onSpeakExample: { text in
                        viewModel.speakSpellingExample(text)
                    },
                    onStopSpeech: {
                        viewModel.stopSpeech()
                    },
                    onComplete: { spellingSummary in
                        viewModel.completeSpelling(spellingSummary)
                    }
                )
            } else if let item = viewModel.currentItem {
                StudyCardView(
                    item: item,
                    progressText: viewModel.progressText,
                    isAnswerVisible: viewModel.isAnswerVisible,
                    isSubmittingRating: viewModel.isSubmittingRating,
                    speechState: viewModel.speechState,
                    onShowAnswer: {
                        viewModel.showAnswer()
                    },
                    onToggleFavorite: {
                        viewModel.handleShortcut(.toggleFavorite, context: modelContext)
                    },
                    onSpeakWord: {
                        viewModel.handleShortcut(.speakWord, context: modelContext)
                    },
                    onSpeakExample: {
                        viewModel.handleShortcut(.speakExample, context: modelContext)
                    },
                    onStopSpeech: {
                        viewModel.handleShortcut(.stopSpeech, context: modelContext)
                    },
                    onRate: { rating in
                        viewModel.handleShortcut(.rate(rating), context: modelContext)
                    }
                )
            } else {
                EmptyStateView(
                    systemImage: "checkmark.circle",
                    title: completedTitle,
                    message: completedMessage
                )
            }
        }
        .task(id: taskIdentity) {
            if viewModel.session == nil {
                applySettings()
                viewModel.loadSession(
                    context: modelContext,
                    wordBookID: wordBookID,
                    mode: mode,
                    dailyNewWordLimit: clampedDailyNewWordLimit,
                    randomizesQueue: randomizeStudyQueue
                )
            }
        }
        .onDisappear {
            viewModel.stopSpeech()
        }
        .onChange(of: japaneseSpeechRate) {
            applySettings()
        }
        .onChange(of: autoSpeakWord) {
            applySettings()
        }
        .onChange(of: autoSpeakExample) {
            applySettings()
        }
    }

    private var clampedDailyNewWordLimit: Int {
        AppSettings.clampedDailyNewWordLimit(dailyNewWordLimit)
    }

    private var taskIdentity: String {
        "\(wordBookID?.uuidString ?? "all")-\(mode.rawValue)"
    }

    private func applySettings() {
        viewModel.updateSettings(
            speechRate: japaneseSpeechRate,
            autoSpeakWord: autoSpeakWord,
            autoSpeakExample: autoSpeakExample
        )
    }
}

#Preview {
    StudyView()
        .modelContainer(PreviewModelContainer.make())
        .frame(width: 760, height: 620)
}
