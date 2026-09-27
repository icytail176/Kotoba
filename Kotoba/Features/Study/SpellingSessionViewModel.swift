import Combine
import Foundation

@MainActor
final class SpellingSessionViewModel: ObservableObject {
    enum Phase: String, Equatable {
        case expression
        case reading
        case completed

        var title: String {
            switch self {
            case .expression: return "单词拼写"
            case .reading: return "假名拼写"
            case .completed: return "拼写完成"
            }
        }
    }

    struct RoundSummary: Equatable {
        let totalCount: Int
        let firstAttemptCorrectCount: Int
        let retryCorrectCount: Int
        let usedHintCount: Int

        nonisolated static let empty = RoundSummary(totalCount: 0, firstAttemptCorrectCount: 0, retryCorrectCount: 0, usedHintCount: 0)
    }

    struct Summary: Equatable {
        let expression: RoundSummary
        let reading: RoundSummary
        let resultsByWordID: [UUID: WordResult]
    }

    struct PhaseResult: Equatable {
        var requiresSpelling = false
        var wrongCount = 0
        var usedHint = false
        var requeueCount = 0
        var passedFirstTry = false
    }

    struct WordResult: Equatable {
        var expression = PhaseResult()
        var reading = PhaseResult()
        var lastTypedAnswer: String?
        var lastExpectedAnswer: String?
        var lastQuestionDirectionRawValue: String?
        var errorTypes: [ReviewErrorType] = []

        var spellingWrongCount: Int { expression.wrongCount }
        var readingWrongCount: Int { reading.wrongCount }
    }

    enum Feedback: Equatable { case correct, incorrect }
    enum QuestionState: Equatable { case answering, submitted }
    enum EnterActionResult: Equatable { case submitted, advanced, completed, ignored }

    @Published private(set) var phase: Phase
    @Published private(set) var questions: [SpellingQuestion]
    @Published private(set) var currentIndex = 0
    @Published private(set) var isAnswerLocked = false
    @Published private(set) var feedback: Feedback?
    @Published private(set) var isHintVisible = false
    @Published private(set) var summary: Summary?
    @Published var answer = ""

    private let normalizer: SpellingAnswerNormalizer
    private let expressionQuestions: [SpellingQuestion]
    private let readingQuestions: [SpellingQuestion]
    private let expressionWordIDs: Set<UUID>
    private let readingWordIDs: Set<UUID>
    private var currentAppearanceHadWrong = false
    private var currentAppearanceUsedHint = false
    private var expressionFirstPasses = Set<UUID>()
    private var expressionRetryPasses = Set<UUID>()
    private var readingFirstPasses = Set<UUID>()
    private var readingRetryPasses = Set<UUID>()
    private var resultsByWordID: [UUID: WordResult] = [:]

    init(
        expressionQuestions: [SpellingQuestion],
        readingQuestions: [SpellingQuestion],
        normalizer: SpellingAnswerNormalizer? = nil
    ) {
        self.expressionQuestions = expressionQuestions
        self.readingQuestions = readingQuestions
        self.expressionWordIDs = Set(expressionQuestions.map(\.wordID))
        self.readingWordIDs = Set(readingQuestions.map(\.wordID))
        self.normalizer = normalizer ?? SpellingAnswerNormalizer()

        if expressionQuestions.isEmpty {
            phase = readingQuestions.isEmpty ? .completed : .reading
            questions = readingQuestions
        } else {
            phase = .expression
            questions = expressionQuestions
        }

        for wordID in expressionWordIDs {
            resultsByWordID[wordID, default: WordResult()].expression.requiresSpelling = true
        }
        for wordID in readingWordIDs {
            resultsByWordID[wordID, default: WordResult()].reading.requiresSpelling = true
        }

        if phase == .completed { finish() }
    }

    var currentQuestion: SpellingQuestion? {
        questions.indices.contains(currentIndex) ? questions[currentIndex] : nil
    }

    var questionState: QuestionState { isAnswerLocked ? .submitted : .answering }
    var primaryActionTitle: String { isAnswerLocked ? "下一题" : "提交" }
    var canRevealHint: Bool { phase == .expression && !isAnswerLocked && currentQuestion != nil }

    var isRetryAppearance: Bool {
        guard let question = currentQuestion, let result = resultsByWordID[question.wordID] else { return false }
        return phase == .expression ? result.expression.requeueCount > 0 : result.reading.requeueCount > 0
    }

    var currentCorrectAnswerWasRequeued: Bool {
        isAnswerLocked
            && feedback == .correct
            && (currentAppearanceHadWrong || currentAppearanceUsedHint)
    }

    var progressText: String {
        guard phase != .completed else { return "拼写完成" }
        let total = phase == .expression ? expressionWordIDs.count : readingWordIDs.count
        let passed = phase == .expression
            ? expressionFirstPasses.count + expressionRetryPasses.count
            : readingFirstPasses.count + readingRetryPasses.count
        return "\(phase.title)  \(min(passed + 1, total)) / \(total)"
    }

    var canSubmit: Bool { canSubmit(isMarkedTextActive: false) }

    func canSubmit(isMarkedTextActive: Bool) -> Bool {
        !isMarkedTextActive && !isAnswerLocked && currentQuestion != nil
            && !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @discardableResult
    func revealHint(isMarkedTextActive: Bool = false) -> Bool {
        guard !isMarkedTextActive, canRevealHint, !isHintVisible, let question = currentQuestion else { return false }
        isHintVisible = true
        currentAppearanceUsedHint = true
        var result = resultsByWordID[question.wordID] ?? WordResult()
        result.expression.usedHint = true
        resultsByWordID[question.wordID] = result
        return true
    }

    @discardableResult
    func submitAnswer(isMarkedTextActive: Bool = false) -> Bool {
        guard canSubmit(isMarkedTextActive: isMarkedTextActive), let question = currentQuestion else { return false }
        let isReading = question.direction == .expressionToReading
        let isCorrect = normalizer.isCorrect(
            answer: answer,
            expected: question.expectedAnswer,
            acceptsKanaOnly: isReading
        )

        if !isCorrect {
            feedback = .incorrect
            currentAppearanceHadWrong = true
            recordWrongAnswer(for: question, typedAnswer: answer)
            return true
        }

        feedback = .correct
        isAnswerLocked = true
        var result = resultsByWordID[question.wordID] ?? WordResult()
        let needsRequeue = currentAppearanceHadWrong || currentAppearanceUsedHint

        switch phase {
        case .expression:
            if needsRequeue {
                result.expression.requeueCount += 1
                questions.append(question)
            } else if result.expression.requeueCount == 0 {
                result.expression.passedFirstTry = true
                expressionFirstPasses.insert(question.wordID)
            } else {
                expressionRetryPasses.insert(question.wordID)
            }
        case .reading:
            if needsRequeue {
                result.reading.requeueCount += 1
                questions.append(question)
            } else if result.reading.requeueCount == 0 {
                result.reading.passedFirstTry = true
                readingFirstPasses.insert(question.wordID)
            } else {
                readingRetryPasses.insert(question.wordID)
            }
        case .completed:
            break
        }

        resultsByWordID[question.wordID] = result
        return true
    }

    @discardableResult
    func handleEnter(isMarkedTextActive: Bool = false) -> EnterActionResult {
        switch questionState {
        case .answering:
            return submitAnswer(isMarkedTextActive: isMarkedTextActive) ? .submitted : .ignored
        case .submitted:
            advance()
            return summary == nil ? .advanced : .completed
        }
    }

    func advance() {
        guard isAnswerLocked else { return }
        currentIndex += 1
        if currentIndex < questions.count {
            resetAppearance()
            return
        }

        if phase == .expression, !readingQuestions.isEmpty {
            phase = .reading
            questions = readingQuestions
            currentIndex = 0
            resetAppearance()
        } else {
            phase = .completed
            finish()
        }
    }

    private func finish() {
        summary = Summary(
            expression: RoundSummary(
                totalCount: expressionWordIDs.count,
                firstAttemptCorrectCount: expressionFirstPasses.count,
                retryCorrectCount: expressionRetryPasses.count,
                usedHintCount: expressionWordIDs.filter { resultsByWordID[$0]?.expression.usedHint == true }.count
            ),
            reading: RoundSummary(
                totalCount: readingWordIDs.count,
                firstAttemptCorrectCount: readingFirstPasses.count,
                retryCorrectCount: readingRetryPasses.count,
                usedHintCount: 0
            ),
            resultsByWordID: resultsByWordID
        )
    }

    private func recordWrongAnswer(for question: SpellingQuestion, typedAnswer: String) {
        var result = resultsByWordID[question.wordID] ?? WordResult()
        result.lastTypedAnswer = typedAnswer
        result.lastExpectedAnswer = question.expectedAnswer
        result.lastQuestionDirectionRawValue = question.direction.rawValue

        switch phase {
        case .expression:
            result.expression.wrongCount += 1
            appendUnique(.spelling, to: &result.errorTypes)
            appendUnique(.expressionDirection, to: &result.errorTypes)
        case .reading:
            result.reading.wrongCount += 1
            appendUnique(.reading, to: &result.errorTypes)
            appendUnique(.readingDirection, to: &result.errorTypes)
        case .completed:
            break
        }
        resultsByWordID[question.wordID] = result
    }

    private func appendUnique(_ errorType: ReviewErrorType, to values: inout [ReviewErrorType]) {
        if !values.contains(errorType) { values.append(errorType) }
    }

    private func resetAppearance() {
        answer = ""
        feedback = nil
        isAnswerLocked = false
        isHintVisible = false
        currentAppearanceHadWrong = false
        currentAppearanceUsedHint = false
    }
}
