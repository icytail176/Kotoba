//
//  SpellingSessionViewModel.swift
//  Kotoba
//
//  Created by Codex on 2026/6/17.
//

import Combine
import Foundation

@MainActor
final class SpellingSessionViewModel: ObservableObject {
    struct Summary: Equatable {
        let totalCount: Int
        let firstAttemptCorrectCount: Int
        let retryCorrectCount: Int
        let remainingIncorrectCount: Int

        var correctCount: Int {
            firstAttemptCorrectCount + retryCorrectCount
        }
    }

    enum Feedback: Equatable {
        case correct
        case incorrect
    }

    @Published private(set) var questions: [SpellingQuestion]
    @Published private(set) var currentIndex = 0
    @Published private(set) var isRetryRound = false
    @Published private(set) var isAnswerLocked = false
    @Published private(set) var feedback: Feedback?
    @Published private(set) var summary: Summary?
    @Published var answer = ""

    private let normalizer: SpellingAnswerNormalizer
    private var retryQuestions: [SpellingQuestion] = []
    private var firstAttemptCorrectCount = 0
    private var retryCorrectCount = 0
    private var remainingIncorrectCount = 0
    private let totalCount: Int

    init(
        questions: [SpellingQuestion],
        normalizer: SpellingAnswerNormalizer? = nil
    ) {
        self.questions = questions
        self.normalizer = normalizer ?? SpellingAnswerNormalizer()
        self.totalCount = questions.count

        if questions.isEmpty {
            summary = Summary(
                totalCount: 0,
                firstAttemptCorrectCount: 0,
                retryCorrectCount: 0,
                remainingIncorrectCount: 0
            )
        }
    }

    var currentQuestion: SpellingQuestion? {
        guard questions.indices.contains(currentIndex) else {
            return nil
        }

        return questions[currentIndex]
    }

    var progressText: String {
        guard !questions.isEmpty else {
            return "拼写完成"
        }

        let prefix = isRetryRound ? "错题重练" : "拼写"
        return "\(prefix) \(min(currentIndex + 1, questions.count)) / \(questions.count)"
    }

    var canSubmit: Bool {
        canSubmit(isMarkedTextActive: false)
    }

    func canSubmit(isMarkedTextActive: Bool) -> Bool {
        !isMarkedTextActive
            && !isAnswerLocked
            && currentQuestion != nil
            && !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @discardableResult
    func submitAnswer(isMarkedTextActive: Bool = false) -> Bool {
        guard canSubmit(isMarkedTextActive: isMarkedTextActive),
              let question = currentQuestion else {
            return false
        }

        let isCorrect = normalizer.isCorrect(
            answer: answer,
            expected: question.expectedAnswer,
            acceptsKanaOnly: question.direction == .expressionToReading
        )
        isAnswerLocked = true

        if isCorrect {
            feedback = .correct
            if isRetryRound {
                retryCorrectCount += 1
            } else {
                firstAttemptCorrectCount += 1
            }
        } else {
            feedback = .incorrect
            if isRetryRound {
                remainingIncorrectCount += 1
            } else {
                retryQuestions.append(question)
            }
        }

        return true
    }

    func advance() {
        guard isAnswerLocked else {
            return
        }

        let nextIndex = currentIndex + 1
        if nextIndex < questions.count {
            currentIndex = nextIndex
            resetAnswerState()
            return
        }

        if !isRetryRound && !retryQuestions.isEmpty {
            questions = retryQuestions
            retryQuestions.removeAll()
            currentIndex = 0
            isRetryRound = true
            resetAnswerState()
            return
        }

        summary = Summary(
            totalCount: totalCount,
            firstAttemptCorrectCount: firstAttemptCorrectCount,
            retryCorrectCount: retryCorrectCount,
            remainingIncorrectCount: remainingIncorrectCount
        )
    }

    private func resetAnswerState() {
        answer = ""
        feedback = nil
        isAnswerLocked = false
    }
}
