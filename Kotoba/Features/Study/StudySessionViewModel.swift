import Combine
import Foundation
import SwiftData

@MainActor
final class StudySessionViewModel: ObservableObject {
    private struct PendingRatingAttempt {
        enum Kind {
            case formal(ReviewRating)
            case reinforcementMastered
        }

        let kind: Kind
        let itemID: UUID
        let now: Date
    }

    enum SpellingOutcome: Equatable {
        case correct, correctedAfterRetry, correctedAfterHint, notRequired

        var title: String {
            switch self {
            case .correct: return "拼写一次通过"
            case .correctedAfterRetry: return "重练通过"
            case .correctedAfterHint: return "使用提示后重练通过"
            case .notRequired: return "不适用"
            }
        }
    }

    struct WordSessionResult: Identifiable, Equatable {
        let id: UUID
        let expression: String
        let reading: String
        let meaningChinese: String
        let cardRating: ReviewRating
        var cardRetryCount: Int
        var isMastered: Bool
        var expressionRequiresSpelling: Bool
        var expressionWrongCount: Int
        var expressionUsedHint: Bool
        var expressionRequeueCount: Int
        var expressionPassedFirstTry: Bool
        var readingRequiresSpelling: Bool
        var readingWrongCount: Int
        var readingRequeueCount: Int
        var readingPassedFirstTry: Bool
        var nextState: LearningState
        var nextReviewAt: Date
        var intervalDays: Int

        var cardRatingTitle: String {
            if isMastered { return "熟练" }
            switch cardRating {
            case .again: return "忘记"
            case .hard: return "模糊"
            case .good: return "认识"
            case .easy: return "熟练"
            }
        }

        var expressionSpellingOutcome: SpellingOutcome {
            guard expressionRequiresSpelling else { return .notRequired }
            if expressionPassedFirstTry { return .correct }
            return expressionUsedHint ? .correctedAfterHint : .correctedAfterRetry
        }

        var readingSpellingOutcome: SpellingOutcome {
            guard readingRequiresSpelling else { return .notRequired }
            return readingPassedFirstTry ? .correct : .correctedAfterRetry
        }

        init(
            word: VocabularyWord,
            cardRating: ReviewRating,
            requiresExpressionSpelling: Bool = false,
            requiresReadingSpelling: Bool = false,
            nextReviewAt: Date
        ) {
            id = word.id
            expression = word.japanese
            reading = word.kana
            meaningChinese = word.chineseMeaning
            self.cardRating = cardRating
            cardRetryCount = 0
            isMastered = word.progress?.state == .suspended
            expressionRequiresSpelling = requiresExpressionSpelling
            expressionWrongCount = 0
            expressionUsedHint = false
            expressionRequeueCount = 0
            expressionPassedFirstTry = false
            readingRequiresSpelling = requiresReadingSpelling
            readingWrongCount = 0
            readingRequeueCount = 0
            readingPassedFirstTry = false
            nextState = word.progress?.state ?? .new
            self.nextReviewAt = nextReviewAt
            intervalDays = word.progress?.intervalDays ?? 0
        }
    }

    struct Summary: Equatable {
        let reviewedCount: Int
        let newWordCount: Int
        let lapseCount: Int
        let expressionSpelling: SpellingSessionViewModel.RoundSummary
        let readingSpelling: SpellingSessionViewModel.RoundSummary
        let wordResults: [WordSessionResult]

        var reviewWordCount: Int { max(0, reviewedCount - newWordCount) }
        var forgottenCount: Int { wordResults.filter { $0.cardRating == .again && !$0.isMastered }.count }
        var fuzzyCount: Int { wordResults.filter { $0.cardRating == .hard && !$0.isMastered }.count }
        var knownCount: Int { wordResults.filter { $0.cardRating == .good && !$0.isMastered }.count }
        var masteredCount: Int { wordResults.filter(\.isMastered).count }

        init(
            reviewedCount: Int,
            newWordCount: Int,
            lapseCount: Int,
            expressionSpelling: SpellingSessionViewModel.RoundSummary = .empty,
            readingSpelling: SpellingSessionViewModel.RoundSummary = .empty,
            wordResults: [WordSessionResult] = []
        ) {
            self.reviewedCount = reviewedCount
            self.newWordCount = newWordCount
            self.lapseCount = lapseCount
            self.expressionSpelling = expressionSpelling
            self.readingSpelling = readingSpelling
            self.wordResults = wordResults
        }
    }

    @Published private(set) var flowState: StudyFlowState = .idle
    @Published private(set) var session: StudySession?
    @Published private(set) var currentIndex = 0
    @Published private(set) var isAnswerVisible = false
    @Published private(set) var isSubmittingRating = false
    @Published private(set) var isSpellingActive = false
    @Published private(set) var spellingWords: [VocabularyWord] = []
    @Published private(set) var expressionSpellingQuestions: [SpellingQuestion] = []
    @Published private(set) var readingSpellingQuestions: [SpellingQuestion] = []
    @Published private(set) var summary: Summary?
    @Published var errorMessage: String?

    private let queueService: StudyQueueService
    private let scheduler: ReviewScheduler
    private let conjugationEngine: ConjugationEngine
    private let saveRatingChanges: (ModelContext) throws -> Void
    private let saveSpellingResults: (ModelContext) throws -> Void
    private var submittedWordIDs = Set<UUID>()
    private var reviewLogsByWordID: [UUID: ReviewLog] = [:]
    private var outcomesByWordID: [UUID: WordSessionResult] = [:]
    private var retryCountsByWordID: [UUID: Int] = [:]
    private var reviewedCount = 0
    private var newWordCount = 0
    private var lapseCount = 0
    private var pendingRatingAttempt: PendingRatingAttempt?
    private var pendingSpellingSummary: SpellingSessionViewModel.Summary?

    init(
        queueService: StudyQueueService? = nil,
        scheduler: ReviewScheduler? = nil,
        conjugationEngine: ConjugationEngine? = nil,
        saveRatingChanges: ((ModelContext) throws -> Void)? = nil,
        saveSpellingResults: ((ModelContext) throws -> Void)? = nil
    ) {
        self.queueService = queueService ?? StudyQueueService()
        self.scheduler = scheduler ?? DefaultReviewScheduler()
        self.conjugationEngine = conjugationEngine ?? ConjugationEngine()
        self.saveRatingChanges = saveRatingChanges ?? { try $0.save() }
        self.saveSpellingResults = saveSpellingResults ?? { try $0.save() }
    }

    var currentItem: StudySession.Item? {
        guard let session, session.items.indices.contains(currentIndex) else { return nil }
        return session.items[currentIndex]
    }
    var currentWord: VocabularyWord? { currentItem?.word }
    var currentConjugation: GeneratedConjugation? { currentWord.flatMap(conjugationEngine.generate) }
    var progressText: String {
        guard let session, !session.items.isEmpty else { return "准备中" }
        return "\(min(currentIndex + 1, session.items.count)) / \(session.items.count)"
    }
    var completedGroupWordCount: Int { reviewedCount }
    var hasRecoverableRatingSaveFailure: Bool { pendingRatingAttempt != nil && errorMessage != nil }
    var hasRecoverableSpellingSaveFailure: Bool { pendingSpellingSummary != nil && errorMessage != nil }

    func cardRetryCount(for wordID: UUID) -> Int { retryCountsByWordID[wordID] ?? 0 }
    func sessionResult(for wordID: UUID) -> WordSessionResult? { outcomesByWordID[wordID] }

    func loadSession(
        context: ModelContext,
        wordBookID: UUID? = nil,
        mode: StudySession.Mode = .mixed,
        now: Date = Date(),
        studyGroupNewWordCount: Int? = nil,
        reviewGroupWordCount: Int? = nil,
        randomizesQueue: Bool = AppSettings.defaultRandomizeStudyQueue
    ) {
        guard [.idle, .cancelled, .error, .summary, .emptyQueue].contains(flowState) else { return }
        do {
            resetSessionMemory()
            flowState = .loadingWords
            let wordBook = try resolveWordBook(id: wordBookID, context: context)
            let built = try queueService.buildSession(
                in: context,
                wordBook: wordBook,
                mode: mode,
                now: now,
                studyGroupNewWordCount: studyGroupNewWordCount ?? AppSettings.defaultStudyGroupNewWordCount,
                reviewGroupWordCount: reviewGroupWordCount ?? AppSettings.defaultReviewGroupWordCount,
                randomizesQueue: randomizesQueue
            )
            session = built
            if built.items.isEmpty {
                flowState = .emptyQueue
            } else {
                flowState = .flashcard
            }
        } catch {
            flowState = .error
            errorMessage = "无法加载今日学习队列：\(error.localizedDescription)"
        }
    }

    func showAnswer() {
        guard currentItem != nil, !isAnswerVisible else { return }
        isAnswerVisible = true
    }

    func toggleFavorite(context: ModelContext) {
        guard let word = currentWord else { return }
        word.isFavorite.toggle()
        word.updatedAt = Date()
        do { try context.save() } catch {
            context.rollback()
            errorMessage = "收藏状态保存失败：\(error.localizedDescription)"
        }
    }

    func submitRating(_ rating: ReviewRating, context: ModelContext, now: Date = Date()) {
        guard isAnswerVisible,
              !isSubmittingRating,
              pendingRatingAttempt == nil,
              let item = currentItem,
              let progress = item.word.progress else { return }
        isSubmittingRating = true
        defer { isSubmittingRating = false }

        let isReinforcement = submittedWordIDs.contains(item.id)
        if isReinforcement {
            handleReinforcement(rating, item: item, progress: progress, context: context, now: now)
            return
        }

        handleFormalRating(rating, item: item, progress: progress, context: context, now: now)
    }

    func retrySavingRating(context: ModelContext) {
        guard !isSubmittingRating,
              let pendingRatingAttempt,
              let item = currentItem,
              item.id == pendingRatingAttempt.itemID,
              let progress = item.word.progress else { return }
        isSubmittingRating = true
        defer { isSubmittingRating = false }
        errorMessage = nil

        switch pendingRatingAttempt.kind {
        case .formal(let rating):
            handleFormalRating(rating, item: item, progress: progress, context: context, now: pendingRatingAttempt.now)
        case .reinforcementMastered:
            handleReinforcement(.easy, item: item, progress: progress, context: context, now: pendingRatingAttempt.now)
        }
    }

    func cancelRatingSaveFailure() {
        guard pendingRatingAttempt != nil else { return }
        pendingRatingAttempt = nil
        errorMessage = nil
    }

    private func handleFormalRating(
        _ rating: ReviewRating,
        item: StudySession.Item,
        progress: LearningProgress,
        context: ModelContext,
        now: Date
    ) {
        let previousState = progress.state
        let previousIntervalDays = progress.intervalDays

        do {
            let previousFormalRating = try latestFormalReviewLog(for: item.word, in: context)?.rating
            let scheduledResult = scheduler.schedule(
                currentState: previousState,
                currentIntervalDays: previousIntervalDays,
                reviewCount: progress.reviewCount,
                lapseCount: progress.lapseCount,
                rating: rating,
                now: now
            )
            let shouldAutoMaster = AutoMasteryPolicy.shouldAutoMaster(
                progressBeforeRating: AutoMasteryProgressSnapshot(
                    state: previousState,
                    intervalDays: previousIntervalDays,
                    isArchived: item.word.isArchived
                ),
                previousFormalRating: previousFormalRating,
                currentRating: rating
            )
            let result = shouldAutoMaster
                ? ReviewScheduleResult(
                    learningState: .suspended,
                    intervalDays: 0,
                    nextReviewAt: now,
                    didLapse: false,
                    reviewCount: scheduledResult.reviewCount,
                    lapseCount: scheduledResult.lapseCount
                )
                : scheduledResult

            apply(result, to: progress, now: now)
            let log = ReviewLog(
                reviewedAt: now,
                rating: rating,
                previousState: previousState,
                nextState: result.learningState,
                previousIntervalDays: previousIntervalDays,
                nextIntervalDays: result.intervalDays,
                scheduledDueAt: result.nextReviewAt,
                errorTypes: rating == .again ? [.meaning] : [],
                word: item.word
            )
            item.word.reviewLogs.append(log)
            item.word.updatedAt = now
            context.insert(log)

            // Progress and its one formal ReviewLog are saved atomically. The
            // session-memory commit below happens only after persistence wins.
            try saveRatingChanges(context)
            StudyStatisticsService.invalidateCache()
            pendingRatingAttempt = nil
            errorMessage = nil
            submittedWordIDs.insert(item.id)
            reviewLogsByWordID[item.id] = log
            reviewedCount += 1
            if item.kind == .newWord { newWordCount += 1 }
            if result.didLapse { lapseCount += 1 }
            let requiresSpelling = result.learningState != .suspended
            outcomesByWordID[item.id] = makeOutcome(
                item: item,
                rating: rating,
                requiresExpressionSpelling: requiresSpelling,
                requiresReadingSpelling: requiresSpelling && containsKanji(item.word.japanese),
                progress: progress
            )
            if requiresSpelling { spellingWords.append(item.word) }
            if rating == .again { enqueue(item) }
            advance(context: context, now: now)
        } catch {
            context.rollback()
            pendingRatingAttempt = PendingRatingAttempt(kind: .formal(rating), itemID: item.id, now: now)
            errorMessage = "评价保存失败：\(error.localizedDescription)"
        }
    }

    func handleShortcut(_ shortcut: StudyShortcut, context: ModelContext, now: Date = Date()) {
        switch shortcut {
        case .showAnswer: showAnswer()
        case .rate(let rating): submitRating(rating, context: context, now: now)
        case .toggleFavorite: toggleFavorite(context: context)
        }
    }

    func completeSpelling(_ spellingSummary: SpellingSessionViewModel.Summary, context: ModelContext, now: Date = Date()) {
        isSpellingActive = false
        pendingSpellingSummary = spellingSummary
        persistSpellingSummary(spellingSummary, context: context)
    }

    func retrySavingSpelling(context: ModelContext) {
        guard let pendingSpellingSummary else { return }
        persistSpellingSummary(pendingSpellingSummary, context: context)
    }

    func continueAfterSpellingSaveFailure() {
        guard let pendingSpellingSummary else { return }
        self.pendingSpellingSummary = nil
        errorMessage = nil
        finish(spellingSummary: pendingSpellingSummary)
    }

    private func persistSpellingSummary(
        _ spellingSummary: SpellingSessionViewModel.Summary,
        context: ModelContext
    ) {
        for (wordID, result) in spellingSummary.resultsByWordID {
            guard var outcome = outcomesByWordID[wordID] else { continue }
            outcome.expressionRequiresSpelling = result.expression.requiresSpelling
            outcome.expressionWrongCount = result.expression.wrongCount
            outcome.expressionUsedHint = result.expression.usedHint
            outcome.expressionRequeueCount = result.expression.requeueCount
            outcome.expressionPassedFirstTry = result.expression.passedFirstTry
            outcome.readingRequiresSpelling = result.reading.requiresSpelling
            outcome.readingWrongCount = result.reading.wrongCount
            outcome.readingRequeueCount = result.reading.requeueCount
            outcome.readingPassedFirstTry = result.reading.passedFirstTry
            outcomesByWordID[wordID] = outcome
            if let log = reviewLogsByWordID[wordID] {
                log.typedAnswer = result.lastTypedAnswer
                log.expectedAnswer = result.lastExpectedAnswer
                log.questionDirectionRawValue = result.lastQuestionDirectionRawValue
                log.readingWrongCount = result.readingWrongCount
                log.spellingWrongCount = result.spellingWrongCount
                log.errorTypes = Array(Set(log.errorTypes + result.errorTypes))
            }
        }
        do {
            try saveSpellingResults(context)
            StudyStatisticsService.invalidateCache()
            pendingSpellingSummary = nil
            errorMessage = nil
            finish(spellingSummary: spellingSummary)
        } catch {
            context.rollback()
            flowState = .error
            errorMessage = "学习进度已保存，但拼写记录保存失败：\(error.localizedDescription)"
        }
    }

    func spellingPhaseChanged(_ phase: SpellingSessionViewModel.Phase) {
        switch phase {
        case .expression: flowState = .spellingExpression
        case .reading: flowState = .spellingReading
        case .completed: break
        }
    }
    func cancelSession() {
        session = nil
        resetSessionMemory()
        flowState = .cancelled
    }

    private func handleReinforcement(
        _ rating: ReviewRating,
        item: StudySession.Item,
        progress: LearningProgress,
        context: ModelContext,
        now: Date
    ) {
        if rating == .easy {
            progress.state = .suspended
            progress.intervalDays = 0
            progress.dueAt = now
            progress.updatedAt = now
            item.word.updatedAt = now
            do {
                // Reinforcement Mastered is an explicit user override. It may
                // suspend progress, but never creates or rewrites a ReviewLog.
                // Session-memory changes commit only after this save succeeds.
                try saveRatingChanges(context)
                StudyStatisticsService.invalidateCache()
                pendingRatingAttempt = nil
                errorMessage = nil
                commitReinforcementMemory(rating, item: item, context: context, now: now)
            } catch {
                context.rollback()
                pendingRatingAttempt = PendingRatingAttempt(
                    kind: .reinforcementMastered,
                    itemID: item.id,
                    now: now
                )
                errorMessage = "强化熟练保存失败：\(error.localizedDescription)"
            }
            return
        }

        // Again / Hard / Good reinforcement is session-only: no scheduler,
        // ReviewLog, reviewCount, lapse, interval, due date, or save operation.
        pendingRatingAttempt = nil
        errorMessage = nil
        commitReinforcementMemory(rating, item: item, context: context, now: now)
    }

    private func commitReinforcementMemory(
        _ rating: ReviewRating,
        item: StudySession.Item,
        context: ModelContext,
        now: Date
    ) {
        let retryCount = (retryCountsByWordID[item.id] ?? 0) + 1
        retryCountsByWordID[item.id] = retryCount
        outcomesByWordID[item.id]?.cardRetryCount = retryCount

        if rating == .easy {
            spellingWords.removeAll { $0.id == item.id }
            outcomesByWordID[item.id]?.isMastered = true
            outcomesByWordID[item.id]?.expressionRequiresSpelling = false
            outcomesByWordID[item.id]?.readingRequiresSpelling = false
            outcomesByWordID[item.id]?.nextState = .suspended
            outcomesByWordID[item.id]?.nextReviewAt = now
            outcomesByWordID[item.id]?.intervalDays = 0
        } else if rating == .again {
            enqueue(item)
        }

        advance(context: context, now: now)
    }

    private func latestFormalReviewLog(
        for word: VocabularyWord,
        in context: ModelContext
    ) throws -> ReviewLog? {
        let wordID = word.id
        var descriptor = FetchDescriptor<ReviewLog>(
            predicate: #Predicate { log in
                log.word?.id == wordID
            },
            sortBy: [SortDescriptor(\.reviewedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func enqueue(_ item: StudySession.Item) {
        guard let session else { return }
        self.session = StudySession(status: .ready, items: session.items + [item])
    }

    private func advance(context: ModelContext, now: Date) {
        guard let session else { return }
        currentIndex += 1
        isAnswerVisible = false
        if currentIndex < session.items.count {
            flowState = submittedWordIDs.contains(session.items[currentIndex].id) ? .flashcardRetry : .flashcard
        } else {
            beginSpellingOrFinish(context: context, now: now)
        }
    }

    private func beginSpellingOrFinish(context: ModelContext, now: Date) {
        let uniqueEligibleWords = Dictionary(grouping: spellingWords, by: \.id).values.compactMap { $0.first }
        spellingWords = uniqueEligibleWords
        if spellingWords.isEmpty {
            finish(spellingSummary: .init(expression: .empty, reading: .empty, resultsByWordID: [:]))
        } else {
            let generator = SpellingQuestionGenerator()
            expressionSpellingQuestions = generator.generateExpressionQuestions(words: spellingWords)
            readingSpellingQuestions = generator.generateReadingQuestions(words: spellingWords)
            if expressionSpellingQuestions.isEmpty && readingSpellingQuestions.isEmpty {
                finish(spellingSummary: .init(expression: .empty, reading: .empty, resultsByWordID: [:]))
            } else {
                isSpellingActive = true
                flowState = expressionSpellingQuestions.isEmpty ? .spellingReading : .spellingExpression
            }
        }
    }

    private func finish(spellingSummary: SpellingSessionViewModel.Summary) {
        let results = outcomesByWordID.values.sorted {
            $0.expression.localizedStandardCompare($1.expression) == .orderedAscending
        }
        summary = Summary(
            reviewedCount: results.count,
            newWordCount: newWordCount,
            lapseCount: lapseCount,
            expressionSpelling: spellingSummary.expression,
            readingSpelling: spellingSummary.reading,
            wordResults: results
        )
        flowState = .summary
    }

    private func apply(_ result: ReviewScheduleResult, to progress: LearningProgress, now: Date) {
        progress.state = result.learningState
        progress.intervalDays = result.intervalDays
        progress.dueAt = result.nextReviewAt
        progress.reviewCount = result.reviewCount
        progress.lapseCount = result.lapseCount
        progress.lastReviewedAt = now
        progress.updatedAt = now
    }

    private func makeOutcome(
        item: StudySession.Item,
        rating: ReviewRating,
        requiresExpressionSpelling: Bool,
        requiresReadingSpelling: Bool,
        progress: LearningProgress
    ) -> WordSessionResult {
        var outcome = WordSessionResult(
            word: item.word,
            cardRating: rating,
            requiresExpressionSpelling: requiresExpressionSpelling,
            requiresReadingSpelling: requiresReadingSpelling,
            nextReviewAt: progress.dueAt
        )
        outcome.isMastered = progress.state == .suspended
        outcome.expressionRequiresSpelling = requiresExpressionSpelling
        outcome.readingRequiresSpelling = requiresReadingSpelling
        outcome.nextState = progress.state
        outcome.intervalDays = progress.intervalDays
        return outcome
    }

    private func resetSessionMemory() {
        currentIndex = 0
        isAnswerVisible = false
        isSubmittingRating = false
        isSpellingActive = false
        spellingWords = []
        expressionSpellingQuestions = []
        readingSpellingQuestions = []
        summary = nil
        errorMessage = nil
        pendingRatingAttempt = nil
        pendingSpellingSummary = nil
        submittedWordIDs.removeAll()
        reviewLogsByWordID.removeAll()
        outcomesByWordID.removeAll()
        retryCountsByWordID.removeAll()
        reviewedCount = 0
        newWordCount = 0
        lapseCount = 0
    }

    private func resolveWordBook(id: UUID?, context: ModelContext) throws -> WordBook? {
        guard let id else { return nil }
        return try context.fetch(FetchDescriptor<WordBook>()).first { $0.id == id }
    }
}
