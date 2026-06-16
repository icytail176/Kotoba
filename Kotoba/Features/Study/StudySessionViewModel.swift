//
//  StudySessionViewModel.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import Combine
import Foundation
import SwiftData

@MainActor
final class StudySessionViewModel: ObservableObject {
    struct Summary: Equatable {
        let reviewedCount: Int
        let newWordCount: Int
        let lapseCount: Int
    }

    @Published private(set) var session: StudySession?
    @Published private(set) var currentIndex = 0
    @Published private(set) var isAnswerVisible = false
    @Published private(set) var isSubmittingRating = false
    @Published private(set) var speechState: SpeechPlaybackState = .idle
    @Published private(set) var summary: Summary?
    @Published var errorMessage: String?

    private let queueService: StudyQueueService
    private let scheduler: ReviewScheduler
    private let speechService: SpeechServicing
    private var submittedWordIDs = Set<UUID>()
    private var reviewedCount = 0
    private var newWordCount = 0
    private var lapseCount = 0
    private var autoSpeakWord = AppSettings.defaultAutoSpeakWord
    private var autoSpeakExample = AppSettings.defaultAutoSpeakExample

    init(
        queueService: StudyQueueService? = nil,
        scheduler: ReviewScheduler? = nil,
        speechService: SpeechServicing? = nil
    ) {
        self.queueService = queueService ?? StudyQueueService()
        self.scheduler = scheduler ?? DefaultReviewScheduler()
        self.speechService = speechService ?? SpeechService()
        self.speechState = self.speechService.state
        self.speechService.onStateChange = { [weak self] state in
            self?.speechState = state
        }
    }

    var currentItem: StudySession.Item? {
        guard let session, session.items.indices.contains(currentIndex) else {
            return nil
        }

        return session.items[currentIndex]
    }

    var currentWord: VocabularyWord? {
        currentItem?.word
    }

    var progressText: String {
        guard let session else {
            return "准备中"
        }

        if session.items.isEmpty {
            return "今日已完成"
        }

        return "\(min(currentIndex + 1, session.items.count)) / \(session.items.count)"
    }

    var isCompleted: Bool {
        summary != nil || session?.status == .completed
    }

    func loadSession(
        context: ModelContext,
        now: Date = Date(),
        dailyNewWordLimit: Int? = nil,
        randomizesQueue: Bool = AppSettings.defaultRandomizeStudyQueue
    ) {
        do {
            session = try queueService.buildSession(
                in: context,
                now: now,
                dailyNewWordLimit: dailyNewWordLimit ?? StudyQueueService.defaultDailyNewWordLimit,
                randomizesQueue: randomizesQueue
            )
            currentIndex = 0
            isAnswerVisible = false
            isSubmittingRating = false
            submittedWordIDs.removeAll()
            reviewedCount = 0
            newWordCount = 0
            lapseCount = 0
            errorMessage = nil

            if session?.status == .completed {
                summary = Summary(reviewedCount: 0, newWordCount: 0, lapseCount: 0)
            } else {
                summary = nil
                speakCurrentWordIfNeeded()
            }
        } catch {
            errorMessage = "无法加载今日学习队列：\(error.localizedDescription)"
        }
    }

    func updateSettings(
        speechRate: Double,
        autoSpeakWord: Bool,
        autoSpeakExample: Bool
    ) {
        speechService.speechRate = Float(AppSettings.clampedJapaneseSpeechRate(speechRate))
        self.autoSpeakWord = autoSpeakWord
        self.autoSpeakExample = autoSpeakExample
    }

    func showAnswer() {
        guard currentItem != nil, !isAnswerVisible else {
            return
        }

        isAnswerVisible = true

        if autoSpeakExample {
            speakExample()
        }
    }

    func toggleFavorite(context: ModelContext) {
        guard let word = currentWord else {
            return
        }

        word.isFavorite.toggle()
        word.updatedAt = Date()

        do {
            try context.save()
        } catch {
            context.rollback()
            errorMessage = "收藏状态保存失败：\(error.localizedDescription)"
        }
    }

    func submitRating(_ rating: ReviewRating, context: ModelContext, now: Date = Date()) {
        guard isAnswerVisible,
              !isSubmittingRating,
              let item = currentItem,
              let progress = item.word.progress,
              !submittedWordIDs.contains(item.id) else {
            return
        }

        isSubmittingRating = true
        defer { isSubmittingRating = false }

        let previousState = progress.state
        let previousIntervalDays = progress.intervalDays
        let result = scheduler.schedule(
            currentState: previousState,
            currentIntervalDays: progress.intervalDays,
            reviewCount: progress.reviewCount,
            lapseCount: progress.lapseCount,
            rating: rating,
            now: now
        )

        progress.state = result.learningState
        progress.intervalDays = result.intervalDays
        progress.dueAt = result.nextReviewAt
        progress.reviewCount = result.reviewCount
        progress.lapseCount = result.lapseCount
        progress.lastReviewedAt = now
        progress.updatedAt = now

        let log = ReviewLog(
            reviewedAt: now,
            rating: rating,
            previousState: previousState,
            nextState: result.learningState,
            previousIntervalDays: previousIntervalDays,
            nextIntervalDays: result.intervalDays,
            scheduledDueAt: result.nextReviewAt,
            word: item.word
        )
        item.word.reviewLogs.append(log)
        item.word.updatedAt = now
        context.insert(log)

        do {
            try context.save()
            submittedWordIDs.insert(item.id)
            reviewedCount += 1

            if item.kind == .newWord {
                newWordCount += 1
            }

            if result.didLapse {
                lapseCount += 1
            }

            advance()
        } catch {
            context.rollback()
            errorMessage = "评价保存失败：\(error.localizedDescription)"
        }
    }

    func handleShortcut(_ shortcut: StudyShortcut, context: ModelContext, now: Date = Date()) {
        switch shortcut {
        case .showAnswer:
            showAnswer()
        case .rate(let rating):
            submitRating(rating, context: context, now: now)
        case .speakWord:
            speakWord()
        case .speakExample:
            speakExample()
        case .stopSpeech:
            stopSpeech()
        case .toggleFavorite:
            toggleFavorite(context: context)
        }
    }

    func speakWord() {
        guard let word = currentWord else {
            return
        }

        speechService.speakWord(word.japanese)
    }

    func speakExample() {
        guard let example = currentWord?.exampleJapanese,
              !example.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        speechService.speakExample(example)
    }

    func stopSpeech() {
        speechService.stop()
    }

    private func advance() {
        guard let session else {
            return
        }

        let nextIndex = currentIndex + 1
        if nextIndex < session.items.count {
            currentIndex = nextIndex
            isAnswerVisible = false
            speakCurrentWordIfNeeded()
        } else {
            currentIndex = session.items.count
            isAnswerVisible = false
            summary = Summary(
                reviewedCount: reviewedCount,
                newWordCount: newWordCount,
                lapseCount: lapseCount
            )
        }
    }

    private func speakCurrentWordIfNeeded() {
        guard autoSpeakWord else {
            return
        }

        speakWord()
    }
}
