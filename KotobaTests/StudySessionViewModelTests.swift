//
//  StudySessionViewModelTests.swift
//  KotobaTests
//
//  Created by Codex on 2026/6/16.
//

import SwiftData
import XCTest
@testable import Kotoba

@MainActor
final class StudySessionViewModelTests: XCTestCase {
    private var calendar: Calendar!
    private var viewModel: StudySessionViewModel!

    override func setUp() {
        super.setUp()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        self.calendar = calendar
        viewModel = StudySessionViewModel(
            queueService: StudyQueueService(calendar: calendar),
            scheduler: DefaultReviewScheduler(calendar: calendar)
        )
    }

    override func tearDown() {
        viewModel = nil
        calendar = nil
        super.tearDown()
    }

    func testNumberShortcutDoesNotSubmitBeforeAnswerIsVisible() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        let word = makeWord("学生", state: .new, dueAt: now, createdAt: now)
        context.insert(word)
        try context.save()

        viewModel.loadSession(context: context, now: now)
        XCTAssertEqual(viewModel.flowState, .flashcard)
        viewModel.handleShortcut(.rate(.good), context: context, now: now)

        XCTAssertFalse(viewModel.isAnswerVisible)
        XCTAssertNil(viewModel.summary)
        XCTAssertEqual(word.reviewLogs.count, 0)
        XCTAssertEqual(word.progress?.state, .new)
    }

    func testSpaceShortcutShowsAnswer() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        context.insert(makeWord("学生", state: .new, dueAt: now, createdAt: now))
        try context.save()

        viewModel.loadSession(context: context, now: now)
        XCTAssertEqual(viewModel.flowState, .flashcard)
        viewModel.handleShortcut(.showAnswer, context: context, now: now)

        XCTAssertTrue(viewModel.isAnswerVisible)
    }

    func testSingleRatingCreatesOneReviewLogAndAdvancesToNextCard() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        let first = makeWord("学生", state: .new, dueAt: now, createdAt: now)
        let second = makeWord("確認", state: .new, dueAt: now, createdAt: addingMinutes(1, to: now))
        context.insert(first)
        context.insert(second)
        try context.save()

        viewModel.loadSession(context: context, now: now)
        let ratedWord = try XCTUnwrap(viewModel.currentWord)
        viewModel.handleShortcut(.showAnswer, context: context, now: now)
        viewModel.handleShortcut(.rate(.good), context: context, now: now)

        XCTAssertEqual(ratedWord.reviewLogs.count, 1)
        XCTAssertEqual(ratedWord.progress?.state, .review)
        XCTAssertEqual(ratedWord.progress?.intervalDays, 2)
        XCTAssertNotEqual(viewModel.currentWord?.id, ratedWord.id)
        XCTAssertEqual(Set([first.id, second.id]), Set([ratedWord.id, try XCTUnwrap(viewModel.currentWord?.id)]))
        XCTAssertFalse(viewModel.isAnswerVisible)
    }

    func testRapidRepeatedRatingDoesNotCreateDuplicateReviewLog() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        let word = makeWord("学生", state: .new, dueAt: now, createdAt: now)
        context.insert(word)
        try context.save()

        viewModel.loadSession(context: context, now: now)
        viewModel.handleShortcut(.showAnswer, context: context, now: now)
        viewModel.handleShortcut(.rate(.good), context: context, now: now)
        viewModel.handleShortcut(.rate(.good), context: context, now: now)
        viewModel.handleShortcut(.rate(.easy), context: context, now: now)

        XCTAssertEqual(word.reviewLogs.count, 1)
        XCTAssertEqual(word.progress?.reviewCount, 1)
        XCTAssertEqual(viewModel.flowState, .spellingExpression)
        XCTAssertNil(viewModel.summary)
        XCTAssertEqual(viewModel.completedGroupWordCount, 1)
    }

    func testKanaOnlyWordStillStartsExpressionSpelling() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        let word = makeWord("学生", state: .new, dueAt: now, createdAt: now)
        context.insert(word)
        try context.save()

        viewModel.loadSession(context: context, now: now)
        viewModel.handleShortcut(.showAnswer, context: context, now: now)
        viewModel.handleShortcut(.rate(.good), context: context, now: now)

        XCTAssertEqual(viewModel.flowState, .spellingExpression)
        XCTAssertTrue(viewModel.isSpellingActive)
        XCTAssertEqual(viewModel.completedGroupWordCount, 1)
        XCTAssertEqual(word.reviewLogs.count, 1)
        XCTAssertEqual(word.progress?.reviewCount, 1)

        XCTAssertNil(viewModel.summary)
    }

    func testSimplifiedSummaryExposesUserFacingCountsAndWordDetails() {
        let dueAt = Date(timeIntervalSinceReferenceDate: 50_000)
        let word = VocabularyWord(
            japanese: "帰る",
            kana: "かえる",
            chineseMeaning: "回去",
            jlptLevel: "N5"
        )
        let result = StudySessionViewModel.WordSessionResult(
            word: word,
            cardRating: .again,
            requiresExpressionSpelling: true,
            requiresReadingSpelling: true,
            nextReviewAt: dueAt
        )
        let summary = StudySessionViewModel.Summary(
            reviewedCount: 10,
            newWordCount: 6,
            lapseCount: 2,
            expressionSpelling: .init(totalCount: 10, firstAttemptCorrectCount: 5, retryCorrectCount: 5, usedHintCount: 2),
            readingSpelling: .init(totalCount: 6, firstAttemptCorrectCount: 4, retryCorrectCount: 2, usedHintCount: 0),
            wordResults: [result]
        )

        XCTAssertEqual(summary.reviewedCount, 10)
        XCTAssertEqual(summary.newWordCount, 6)
        XCTAssertEqual(summary.reviewWordCount, 4)
        XCTAssertEqual(summary.lapseCount, 2)
        XCTAssertEqual(summary.expressionSpelling.totalCount, 10)
        XCTAssertEqual(summary.expressionSpelling.firstAttemptCorrectCount, 5)
        XCTAssertEqual(summary.expressionSpelling.retryCorrectCount, 5)
        XCTAssertEqual(summary.expressionSpelling.usedHintCount, 2)
        XCTAssertEqual(
            summary.expressionSpelling.firstAttemptCorrectCount + summary.expressionSpelling.retryCorrectCount,
            summary.expressionSpelling.totalCount
        )
        XCTAssertLessThanOrEqual(
            summary.expressionSpelling.usedHintCount,
            summary.expressionSpelling.retryCorrectCount
        )
        XCTAssertEqual(summary.readingSpelling.totalCount, 6)
        XCTAssertEqual(
            summary.readingSpelling.firstAttemptCorrectCount + summary.readingSpelling.retryCorrectCount,
            summary.readingSpelling.totalCount
        )
        XCTAssertEqual(result.cardRatingTitle, "忘记")
        XCTAssertEqual(result.expressionSpellingOutcome.title, "重练通过")
        XCTAssertEqual(result.nextReviewAt, dueAt)
    }

    func testCardQueueAutomaticallyStartsSpelling() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        let word = makeWord("学生", state: .new, dueAt: now, createdAt: now)
        word.kana = "がくせい"
        context.insert(word)
        try context.save()

        viewModel.loadSession(context: context, now: now)
        viewModel.handleShortcut(.showAnswer, context: context, now: now)
        viewModel.handleShortcut(.rate(.good), context: context, now: now)
        XCTAssertEqual(viewModel.flowState, .spellingExpression)
        XCTAssertTrue(viewModel.isSpellingActive)

        viewModel.spellingPhaseChanged(.reading)

        XCTAssertEqual(viewModel.flowState, .spellingReading)
    }

    func testSummaryContainsTraceableWordResultAndReviewLogErrorDetails() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        let word = makeWord("確認", state: .new, dueAt: now, createdAt: now)
        word.kana = "かくにん"
        word.chineseMeaning = "确认"
        context.insert(word)
        try context.save()

        viewModel.loadSession(context: context, now: now)
        viewModel.handleShortcut(.showAnswer, context: context, now: now)
        viewModel.handleShortcut(.rate(.good), context: context, now: now)

        var spellingResult = SpellingSessionViewModel.WordResult()
        spellingResult.expression.requiresSpelling = true
        spellingResult.expression.wrongCount = 1
        spellingResult.expression.requeueCount = 1
        spellingResult.lastTypedAnswer = "うえて"
        spellingResult.lastExpectedAnswer = "確認"
        spellingResult.lastQuestionDirectionRawValue = SpellingQuestionDirection.meaningToExpression.rawValue
        spellingResult.errorTypes = [.spelling, .expressionDirection]

        viewModel.completeSpelling(
            .init(
                expression: .init(totalCount: 1, firstAttemptCorrectCount: 0, retryCorrectCount: 1, usedHintCount: 0),
                reading: .empty,
                resultsByWordID: [word.id: spellingResult]
            ),
            context: context,
            now: addingMinutes(3, to: now)
        )

        let wordResult = try XCTUnwrap(viewModel.summary?.wordResults.first)
        XCTAssertEqual(wordResult.expression, "確認")
        XCTAssertEqual(wordResult.cardRating, .good)
        XCTAssertEqual(wordResult.cardRatingTitle, "认识")
        XCTAssertEqual(wordResult.expressionSpellingOutcome, .correctedAfterRetry)
        XCTAssertEqual(wordResult.expressionSpellingOutcome.title, "重练通过")

        let log = try XCTUnwrap(word.reviewLogs.first)
        XCTAssertEqual(log.rating, .good)
        XCTAssertEqual(Set(log.errorTypes), Set([.spelling, .expressionDirection]))
        XCTAssertEqual(log.typedAnswer, "うえて")
        XCTAssertEqual(log.expectedAnswer, "確認")
        XCTAssertEqual(log.questionDirectionRawValue, SpellingQuestionDirection.meaningToExpression.rawValue)
        XCTAssertEqual(log.spellingWrongCount, 1)
    }

    func testAgainReinforcesUntilPassWithoutRepeatedSchedulingOrLogs() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        let word = makeWord("確認", state: .review, dueAt: now, createdAt: now)
        context.insert(word)
        try context.save()

        viewModel.loadSession(context: context, now: now, studyGroupNewWordCount: 10, reviewGroupWordCount: 20)

        viewModel.handleShortcut(.showAnswer, context: context, now: now)
        viewModel.handleShortcut(.rate(.again), context: context, now: now)
        XCTAssertEqual(viewModel.currentWord?.id, word.id)
        XCTAssertEqual(viewModel.flowState, .flashcardRetry)

        viewModel.handleShortcut(.showAnswer, context: context, now: addingMinutes(1, to: now))
        viewModel.handleShortcut(.rate(.again), context: context, now: addingMinutes(1, to: now))
        XCTAssertEqual(viewModel.currentWord?.id, word.id)

        viewModel.handleShortcut(.showAnswer, context: context, now: addingMinutes(2, to: now))
        viewModel.handleShortcut(.rate(.good), context: context, now: addingMinutes(2, to: now))
        XCTAssertEqual(viewModel.flowState, .spellingExpression)
        XCTAssertEqual(word.progress?.state, .relearning)
        XCTAssertEqual(word.progress?.intervalDays, 0)
        XCTAssertEqual(word.progress?.reviewCount, 1)
        XCTAssertEqual(word.reviewLogs.count, 1)
        XCTAssertEqual(word.reviewLogs.first?.rating, .again)

        var spellingResult = SpellingSessionViewModel.WordResult()
        spellingResult.expression.requiresSpelling = true
        spellingResult.expression.passedFirstTry = true
        spellingResult.reading.requiresSpelling = true
        spellingResult.reading.passedFirstTry = true
        viewModel.completeSpelling(
            .init(
                expression: .init(totalCount: 1, firstAttemptCorrectCount: 1, retryCorrectCount: 0, usedHintCount: 0),
                reading: .init(totalCount: 1, firstAttemptCorrectCount: 1, retryCorrectCount: 0, usedHintCount: 0),
                resultsByWordID: [word.id: spellingResult]
            ),
            context: context
        )
        XCTAssertEqual(viewModel.flowState, .summary)

        XCTAssertEqual(word.progress?.lapseCount, 1)
        XCTAssertEqual(word.progress?.reviewCount, 1)
        XCTAssertEqual(word.reviewLogs.count, 1)
        XCTAssertEqual(viewModel.summary?.reviewedCount, 1)
        XCTAssertEqual(viewModel.summary?.lapseCount, 1)
        XCTAssertEqual(viewModel.summary?.wordResults.first?.cardRating, .again)
        XCTAssertEqual(viewModel.summary?.wordResults.first?.cardRetryCount, 2)
    }

    func testAgainThenMasteredKeepsFirstFormalRatingAcrossAllInitialStates() throws {
        for state in [LearningState.new, .learning, .review, .relearning] {
            let container = try makeInMemoryTestContainer()
            let context = container.mainContext
            let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)
            let word = makeWord("確認", state: state, dueAt: now, createdAt: now)
            word.kana = "かくにん"
            context.insert(word)
            try context.save()
            let subject = StudySessionViewModel(
                queueService: StudyQueueService(calendar: calendar),
                scheduler: DefaultReviewScheduler(calendar: calendar)
            )

            subject.loadSession(context: context, now: now)
            subject.showAnswer()
            subject.submitRating(.again, context: context, now: now)
            subject.showAnswer()
            subject.submitRating(.easy, context: context, now: addingMinutes(1, to: now))

            XCTAssertEqual(word.progress?.state, .suspended, "initial state \(state)")
            XCTAssertEqual(word.reviewLogs.count, 1, "initial state \(state)")
            XCTAssertEqual(word.reviewLogs.first?.rating, .again, "initial state \(state)")
            XCTAssertEqual(word.reviewLogs.first?.previousState, state, "initial state \(state)")
            XCTAssertEqual(subject.summary?.masteredCount, 1, "initial state \(state)")
        }
    }

    func testZeroQuestionSpellingAutomaticallySkipsOrStartsAvailableRound() throws {
        let cases: [(String, String, String, StudyFlowState, Int, Int)] = [
            ("確認", "かくにん", "", .spellingReading, 0, 1),
            ("たべる", "たべる", "吃", .spellingExpression, 1, 0),
            ("たべる", "たべる", "", .summary, 0, 0)
        ]

        for (expression, reading, meaning, expectedState, expressionCount, readingCount) in cases {
            let container = try makeInMemoryTestContainer()
            let context = container.mainContext
            let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)
            let word = makeWord(expression, state: .new, dueAt: now, createdAt: now)
            word.kana = reading
            word.chineseMeaning = meaning
            context.insert(word)
            try context.save()
            let subject = StudySessionViewModel(
                queueService: StudyQueueService(calendar: calendar),
                scheduler: DefaultReviewScheduler(calendar: calendar)
            )

            subject.loadSession(context: context, now: now)
            subject.showAnswer()
            subject.submitRating(.good, context: context, now: now)

            XCTAssertEqual(subject.flowState, expectedState)
            XCTAssertEqual(subject.expressionSpellingQuestions.count, expressionCount)
            XCTAssertEqual(subject.readingSpellingQuestions.count, readingCount)
            XCTAssertEqual(subject.isSpellingActive, expectedState != .summary)
        }
    }

    func testSpellingSaveFailureIsRecoverableWithoutRollingBackCardOrDuplicatingLog() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        let word = makeWord("確認", state: .new, dueAt: now, createdAt: now)
        word.kana = "かくにん"
        word.chineseMeaning = "确认"
        context.insert(word)
        try context.save()
        var saveAttempts = 0
        struct ExpectedFailure: Error {}
        let subject = StudySessionViewModel(
            queueService: StudyQueueService(calendar: calendar),
            scheduler: DefaultReviewScheduler(calendar: calendar),
            saveSpellingResults: { context in
                saveAttempts += 1
                if saveAttempts == 1 { throw ExpectedFailure() }
                try context.save()
            }
        )
        subject.loadSession(context: context, now: now)
        subject.showAnswer()
        subject.submitRating(.good, context: context, now: now)

        var result = SpellingSessionViewModel.WordResult()
        result.expression.requiresSpelling = true
        result.expression.wrongCount = 1
        result.errorTypes = [.spelling]
        let spellingSummary = SpellingSessionViewModel.Summary(
            expression: .init(totalCount: 1, firstAttemptCorrectCount: 0, retryCorrectCount: 1, usedHintCount: 0),
            reading: .empty,
            resultsByWordID: [word.id: result]
        )
        subject.completeSpelling(spellingSummary, context: context)

        XCTAssertEqual(word.progress?.state, .review)
        XCTAssertEqual(word.reviewLogs.count, 1)
        XCTAssertNil(subject.summary)
        XCTAssertTrue(subject.hasRecoverableSpellingSaveFailure)
        XCTAssertTrue(subject.errorMessage?.contains("学习进度已保存") == true)

        subject.retrySavingSpelling(context: context)

        XCTAssertEqual(saveAttempts, 2)
        XCTAssertEqual(word.reviewLogs.count, 1)
        XCTAssertEqual(word.reviewLogs.first?.spellingWrongCount, 1)
        XCTAssertEqual(subject.flowState, .summary)
        XCTAssertNotNil(subject.summary)
        XCTAssertFalse(subject.hasRecoverableSpellingSaveFailure)
    }

    func testUserCanContinueAfterSpellingSaveFailureWithCardProgressIntact() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        let word = makeWord("確認", state: .new, dueAt: now, createdAt: now)
        word.kana = "かくにん"
        word.chineseMeaning = "确认"
        context.insert(word)
        try context.save()
        struct ExpectedFailure: Error {}
        let subject = StudySessionViewModel(
            queueService: StudyQueueService(calendar: calendar),
            scheduler: DefaultReviewScheduler(calendar: calendar),
            saveSpellingResults: { _ in throw ExpectedFailure() }
        )
        subject.loadSession(context: context, now: now)
        subject.showAnswer()
        subject.submitRating(.good, context: context, now: now)
        let spellingSummary = SpellingSessionViewModel.Summary(
            expression: .init(totalCount: 1, firstAttemptCorrectCount: 1, retryCorrectCount: 0, usedHintCount: 0),
            reading: .empty,
            resultsByWordID: [:]
        )
        subject.completeSpelling(spellingSummary, context: context)
        subject.continueAfterSpellingSaveFailure()

        XCTAssertEqual(word.progress?.state, .review)
        XCTAssertEqual(word.reviewLogs.count, 1)
        XCTAssertEqual(subject.flowState, .summary)
        XCTAssertNotNil(subject.summary)
        XCTAssertNil(subject.errorMessage)
    }

    func testFavoriteShortcutTogglesFavorite() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        let word = makeWord("学生", state: .new, dueAt: now, createdAt: now)
        context.insert(word)
        try context.save()

        viewModel.loadSession(context: context, now: now)
        viewModel.handleShortcut(.toggleFavorite, context: context, now: now)

        XCTAssertTrue(word.isFavorite)
    }

    func testMasteredSuspendsCreatesOneLogAndSkipsSpelling() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        let word = makeWord("食べる", state: .review, dueAt: now, createdAt: now)
        word.kana = "たべる"
        context.insert(word)
        try context.save()

        viewModel.loadSession(context: context, now: now)
        viewModel.showAnswer()
        viewModel.submitRating(.easy, context: context, now: now)

        XCTAssertEqual(word.progress?.state, .suspended)
        XCTAssertEqual(word.reviewLogs.count, 1)
        XCTAssertEqual(word.reviewLogs.first?.nextState, .suspended)
        XCTAssertEqual(viewModel.flowState, .summary)
        XCTAssertEqual(viewModel.summary?.masteredCount, 1)
        XCTAssertEqual(viewModel.summary?.expressionSpelling.totalCount, 0)
        XCTAssertEqual(viewModel.summary?.wordResults.first?.expressionSpellingOutcome, .notRequired)
    }

    func testReinforcementMasteredSaveFailureKeepsSessionMemoryRetryableThenCommitsOnce() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        let word = makeWord("確認", state: .review, dueAt: now, createdAt: now)
        word.kana = "かくにん"
        word.progress?.intervalDays = 12
        context.insert(word)
        try context.save()
        var saveAttempts = 0
        struct ExpectedFailure: Error {}
        let subject = StudySessionViewModel(
            queueService: StudyQueueService(calendar: calendar),
            scheduler: DefaultReviewScheduler(calendar: calendar),
            saveRatingChanges: { context in
                saveAttempts += 1
                if saveAttempts == 2 { throw ExpectedFailure() }
                try context.save()
            }
        )

        subject.loadSession(context: context, now: now)
        subject.showAnswer()
        subject.submitRating(.again, context: context, now: now)
        let formalDueAt = try XCTUnwrap(word.progress?.dueAt)
        let memoryBeforeFailure = try XCTUnwrap(subject.sessionResult(for: word.id))
        let spellingIDsBeforeFailure = subject.spellingWords.map(\.id)
        let indexBeforeFailure = subject.currentIndex

        subject.showAnswer()
        subject.submitRating(.easy, context: context, now: addingMinutes(1, to: now))

        XCTAssertEqual(saveAttempts, 2)
        XCTAssertTrue(subject.hasRecoverableRatingSaveFailure)
        XCTAssertEqual(word.progress?.state, .relearning)
        XCTAssertEqual(word.progress?.intervalDays, 0)
        XCTAssertEqual(word.progress?.dueAt, formalDueAt)
        XCTAssertEqual(subject.spellingWords.map(\.id), spellingIDsBeforeFailure)
        XCTAssertEqual(subject.sessionResult(for: word.id), memoryBeforeFailure)
        XCTAssertEqual(subject.cardRetryCount(for: word.id), 0)
        XCTAssertEqual(subject.currentIndex, indexBeforeFailure)
        XCTAssertEqual(subject.currentWord?.id, word.id)
        XCTAssertEqual(word.reviewLogs.count, 1)
        XCTAssertEqual(word.reviewLogs.first?.rating, .again)

        subject.retrySavingRating(context: context)

        XCTAssertEqual(saveAttempts, 3)
        XCTAssertFalse(subject.hasRecoverableRatingSaveFailure)
        XCTAssertEqual(word.progress?.state, .suspended)
        XCTAssertEqual(word.progress?.intervalDays, 0)
        XCTAssertEqual(subject.spellingWords.map(\.id), [])
        XCTAssertEqual(subject.cardRetryCount(for: word.id), 1)
        XCTAssertEqual(subject.currentIndex, indexBeforeFailure + 1)
        XCTAssertEqual(subject.summary?.masteredCount, 1)
        XCTAssertEqual(subject.sessionResult(for: word.id)?.isMastered, true)
        XCTAssertEqual(word.reviewLogs.count, 1)
        XCTAssertEqual(word.reviewLogs.first?.rating, .again)
    }

    func testGoodAtThirtyTwoDaysSchedulesSixtyWithoutAutomaticMastery() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        let word = makeWord("確認", state: .review, dueAt: now, createdAt: now)
        word.kana = "かくにん"
        word.progress?.intervalDays = 32
        word.progress?.reviewCount = 6
        let previous = addFormalLog(to: word, rating: .good, intervalDays: 32, reviewedAt: addingMinutes(-1, to: now))
        context.insert(word)
        context.insert(previous)
        try context.save()

        viewModel.loadSession(context: context, now: now)
        viewModel.showAnswer()
        viewModel.submitRating(.good, context: context, now: now)

        XCTAssertEqual(word.progress?.state, .review)
        XCTAssertEqual(word.progress?.intervalDays, 60)
        XCTAssertEqual(word.progress?.dueAt, calendar.date(byAdding: .day, value: 60, to: now))
        XCTAssertEqual(word.reviewLogs.count, 2)
        XCTAssertEqual(word.reviewLogs.max(by: { $0.reviewedAt < $1.reviewedAt })?.nextState, .review)
        XCTAssertEqual(viewModel.spellingWords.map(\.id), [word.id])
        XCTAssertEqual(viewModel.flowState, .spellingExpression)

        viewModel.completeSpelling(
            .init(expression: .empty, reading: .empty, resultsByWordID: [:]),
            context: context,
            now: addingMinutes(1, to: now)
        )

        XCTAssertEqual(word.progress?.state, .review)
        XCTAssertEqual(word.progress?.intervalDays, 60)
        XCTAssertEqual(word.reviewLogs.count, 2)
        XCTAssertEqual(viewModel.flowState, .summary)
    }

    func testGoodAtSixtyAfterPreviousGoodAutoMastersAtomically() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = makeDate(year: 2026, month: 8, day: 15, hour: 9)
        let book = WordBook(name: "自动熟练")
        let word = makeWord("確認", state: .review, dueAt: now, createdAt: now)
        word.kana = "かくにん"
        word.wordBook = book
        word.progress?.intervalDays = 60
        word.progress?.reviewCount = 7
        let previous = addFormalLog(
            to: word,
            rating: .good,
            intervalDays: 60,
            reviewedAt: try XCTUnwrap(calendar.date(byAdding: .day, value: -60, to: now))
        )
        context.insert(book)
        context.insert(word)
        context.insert(previous)
        try context.save()

        viewModel.loadSession(context: context, wordBookID: book.id, now: now)
        viewModel.showAnswer()
        viewModel.submitRating(.good, context: context, now: now)

        XCTAssertEqual(word.progress?.state, .suspended)
        XCTAssertEqual(word.progress?.intervalDays, 0)
        XCTAssertEqual(word.progress?.dueAt, now)
        XCTAssertEqual(word.progress?.reviewCount, 8)
        XCTAssertEqual(word.reviewLogs.count, 2)
        let currentLog = try XCTUnwrap(word.reviewLogs.first { $0.reviewedAt == now })
        XCTAssertEqual(currentLog.rating, .good)
        XCTAssertEqual(currentLog.previousState, .review)
        XCTAssertEqual(currentLog.nextState, .suspended)
        XCTAssertEqual(currentLog.previousIntervalDays, 60)
        XCTAssertEqual(currentLog.nextIntervalDays, 0)
        XCTAssertEqual(currentLog.scheduledDueAt, now)
        XCTAssertTrue(viewModel.spellingWords.isEmpty)
        XCTAssertEqual(viewModel.summary?.masteredCount, 1)

        let nextQueue = try StudyQueueService(calendar: calendar).buildSession(
            in: context,
            wordBook: book,
            now: addingMinutes(1, to: now),
            randomizesQueue: false
        )
        XCTAssertTrue(nextQueue.items.isEmpty)
        let summary = WordBookService().summary(for: book, selectedID: book.id, now: now)
        XCTAssertEqual(summary.masteredWordCount, 1)
        let dashboard = try HomeDashboardService().makeSnapshot(
            in: context,
            selectedIDString: book.id.uuidString,
            now: now
        ).snapshot
        XCTAssertEqual(dashboard.masteredWordCount, 1)
        XCTAssertEqual(dashboard.dueReviewCount, 0)
    }

    func testHardThenGoodThenGoodAtSixtyAutoMastersOnlyOnSecondGood() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let firstDue = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        let word = makeWord("確認", state: .review, dueAt: firstDue, createdAt: firstDue)
        word.kana = "かくにん"
        word.progress?.intervalDays = 60
        let previous = addFormalLog(to: word, rating: .good, intervalDays: 60, reviewedAt: addingMinutes(-1, to: firstDue))
        context.insert(word)
        context.insert(previous)
        try context.save()

        let hardSession = makeViewModel()
        hardSession.loadSession(context: context, now: firstDue)
        hardSession.showAnswer()
        hardSession.submitRating(.hard, context: context, now: firstDue)
        XCTAssertEqual(word.progress?.state, .review)
        XCTAssertEqual(word.progress?.intervalDays, 60)

        let firstGoodAt = try XCTUnwrap(word.progress?.dueAt)
        let firstGoodSession = makeViewModel()
        firstGoodSession.loadSession(context: context, now: firstGoodAt)
        firstGoodSession.showAnswer()
        firstGoodSession.submitRating(.good, context: context, now: firstGoodAt)
        XCTAssertEqual(word.progress?.state, .review)
        XCTAssertEqual(word.progress?.intervalDays, 60)

        let secondGoodAt = try XCTUnwrap(word.progress?.dueAt)
        let secondGoodSession = makeViewModel()
        secondGoodSession.loadSession(context: context, now: secondGoodAt)
        secondGoodSession.showAnswer()
        secondGoodSession.submitRating(.good, context: context, now: secondGoodAt)

        XCTAssertEqual(word.progress?.state, .suspended)
        XCTAssertEqual(word.progress?.intervalDays, 0)
        XCTAssertEqual(word.reviewLogs.count, 4)
        let orderedRatings = word.reviewLogs.sorted { $0.reviewedAt < $1.reviewedAt }.map(\.rating)
        XCTAssertEqual(orderedRatings, [.good, .hard, .good, .good])
    }

    func testAgainAtSixtyAfterPreviousGoodLapsesInsteadOfAutoMastering() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        let word = makeWord("確認", state: .review, dueAt: now, createdAt: now)
        word.progress?.intervalDays = 60
        word.progress?.lapseCount = 2
        let previous = addFormalLog(to: word, rating: .good, intervalDays: 60, reviewedAt: addingMinutes(-1, to: now))
        context.insert(word)
        context.insert(previous)
        try context.save()

        viewModel.loadSession(context: context, now: now)
        viewModel.showAnswer()
        viewModel.submitRating(.again, context: context, now: now)

        XCTAssertEqual(word.progress?.state, .relearning)
        XCTAssertEqual(word.progress?.intervalDays, 0)
        XCTAssertEqual(word.progress?.lapseCount, 3)
        XCTAssertEqual(word.reviewLogs.count, 2)
        XCTAssertEqual(word.reviewLogs.first { $0.reviewedAt == now }?.rating, .again)
    }

    func testAutomaticMasterySaveFailureRollsBackProgressAndLogThenRetriesOnce() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = makeDate(year: 2026, month: 8, day: 15, hour: 9)
        let word = makeWord("確認", state: .review, dueAt: now, createdAt: now)
        word.kana = "かくにん"
        word.progress?.intervalDays = 60
        word.progress?.reviewCount = 7
        let previous = addFormalLog(to: word, rating: .good, intervalDays: 60, reviewedAt: addingMinutes(-1, to: now))
        context.insert(word)
        context.insert(previous)
        try context.save()
        var saveAttempts = 0
        struct ExpectedFailure: Error {}
        let subject = makeViewModel(saveRatingChanges: { context in
            saveAttempts += 1
            if saveAttempts == 1 { throw ExpectedFailure() }
            try context.save()
        })

        subject.loadSession(context: context, now: now)
        subject.showAnswer()
        subject.submitRating(.good, context: context, now: now)

        XCTAssertEqual(saveAttempts, 1)
        XCTAssertTrue(subject.hasRecoverableRatingSaveFailure)
        XCTAssertEqual(word.progress?.state, .review)
        XCTAssertEqual(word.progress?.intervalDays, 60)
        XCTAssertEqual(word.progress?.reviewCount, 7)
        XCTAssertEqual(word.reviewLogs.count, 1)
        XCTAssertEqual(subject.currentWord?.id, word.id)
        XCTAssertEqual(subject.currentIndex, 0)
        XCTAssertEqual(subject.completedGroupWordCount, 0)
        XCTAssertTrue(subject.spellingWords.isEmpty)

        subject.retrySavingRating(context: context)

        XCTAssertEqual(saveAttempts, 2)
        XCTAssertEqual(word.progress?.state, .suspended)
        XCTAssertEqual(word.progress?.intervalDays, 0)
        XCTAssertEqual(word.reviewLogs.count, 2)
        XCTAssertEqual(word.reviewLogs.filter { $0.reviewedAt == now }.count, 1)
        XCTAssertEqual(word.reviewLogs.first { $0.reviewedAt == now }?.rating, .good)
        XCTAssertEqual(word.reviewLogs.first { $0.reviewedAt == now }?.nextState, .suspended)
        XCTAssertEqual(subject.summary?.masteredCount, 1)
    }

    func testRelearningHardAndGoodCreateExactlyOneFormalLog() throws {
        for (rating, expectedDays) in [(ReviewRating.hard, 1), (.good, 2)] {
            let container = try makeInMemoryTestContainer()
            let context = container.mainContext
            let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)
            let word = makeWord("確認", state: .relearning, dueAt: now, createdAt: now)
            word.progress?.reviewCount = 4
            word.progress?.lapseCount = 2
            context.insert(word)
            try context.save()
            let subject = makeViewModel()

            subject.loadSession(context: context, now: now)
            subject.showAnswer()
            subject.submitRating(rating, context: context, now: now)

            XCTAssertEqual(word.progress?.state, .review)
            XCTAssertEqual(word.progress?.intervalDays, expectedDays)
            XCTAssertEqual(word.progress?.dueAt, calendar.date(byAdding: .day, value: expectedDays, to: now))
            XCTAssertEqual(word.progress?.reviewCount, 5)
            XCTAssertEqual(word.progress?.lapseCount, 2)
            XCTAssertEqual(word.reviewLogs.count, 1)
            XCTAssertEqual(word.reviewLogs.first?.rating, rating)
            XCTAssertEqual(word.reviewLogs.first?.previousState, .relearning)
            XCTAssertEqual(word.reviewLogs.first?.nextState, .review)
            XCTAssertEqual(word.reviewLogs.first?.scheduledDueAt, word.progress?.dueAt)
        }
    }

    func testFormalHardCreatesExactlyOneLogForNewAndReviewWords() throws {
        let cases: [(LearningState, Int, Int)] = [(.new, 0, 1), (.review, 10, 12)]
        for (state, previousDays, expectedDays) in cases {
            let container = try makeInMemoryTestContainer()
            let context = container.mainContext
            let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)
            let word = makeWord("確認", state: state, dueAt: now, createdAt: now)
            word.progress?.intervalDays = previousDays
            word.progress?.reviewCount = 3
            context.insert(word)
            try context.save()
            let subject = makeViewModel()

            subject.loadSession(context: context, now: now)
            subject.showAnswer()
            subject.submitRating(.hard, context: context, now: now)

            XCTAssertEqual(word.progress?.reviewCount, 4)
            XCTAssertEqual(word.reviewLogs.count, 1)
            let log = try XCTUnwrap(word.reviewLogs.first)
            XCTAssertEqual(log.rating, .hard)
            XCTAssertEqual(log.previousState, state)
            XCTAssertEqual(log.nextState, .review)
            XCTAssertEqual(log.previousIntervalDays, previousDays)
            XCTAssertEqual(log.nextIntervalDays, expectedDays)
            XCTAssertEqual(log.scheduledDueAt, calendar.date(byAdding: .day, value: expectedDays, to: now))
        }
    }

    func testFormalRatingSaveFailureRollsBackThenRetriesWithoutDuplicateLog() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        let word = makeWord("確認", state: .new, dueAt: now, createdAt: now)
        word.kana = "かくにん"
        context.insert(word)
        try context.save()
        var saveAttempts = 0
        struct ExpectedFailure: Error {}
        let subject = makeViewModel(saveRatingChanges: { context in
            saveAttempts += 1
            if saveAttempts == 1 { throw ExpectedFailure() }
            try context.save()
        })

        subject.loadSession(context: context, now: now)
        subject.showAnswer()
        subject.submitRating(.good, context: context, now: now)

        XCTAssertEqual(word.progress?.state, .new)
        XCTAssertEqual(word.progress?.reviewCount, 0)
        XCTAssertEqual(word.reviewLogs.count, 0)
        XCTAssertEqual(subject.currentWord?.id, word.id)
        XCTAssertEqual(subject.currentIndex, 0)
        XCTAssertEqual(subject.completedGroupWordCount, 0)
        XCTAssertTrue(subject.spellingWords.isEmpty)
        XCTAssertTrue(subject.hasRecoverableRatingSaveFailure)

        subject.retrySavingRating(context: context)

        XCTAssertEqual(saveAttempts, 2)
        XCTAssertEqual(word.progress?.state, .review)
        XCTAssertEqual(word.progress?.reviewCount, 1)
        XCTAssertEqual(word.reviewLogs.count, 1)
        XCTAssertEqual(word.reviewLogs.first?.rating, .good)
        XCTAssertEqual(subject.completedGroupWordCount, 1)
        XCTAssertEqual(subject.spellingWords.map(\.id), [word.id])
        XCTAssertFalse(subject.hasRecoverableRatingSaveFailure)
    }

    func testFormalRatingPersistsAcrossNewContextAndRebuildsDueQueue() throws {
        let container = try makeInMemoryTestContainer()
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        let wordID: UUID
        let expectedDueAt: Date

        do {
            let context = ModelContext(container)
            let word = makeWord("確認", state: .review, dueAt: now, createdAt: now)
            word.progress?.intervalDays = 10
            word.progress?.reviewCount = 4
            context.insert(word)
            try context.save()
            wordID = word.id
            let subject = makeViewModel()
            subject.loadSession(context: context, now: now)
            subject.showAnswer()
            subject.submitRating(.good, context: context, now: now)
            expectedDueAt = try XCTUnwrap(word.progress?.dueAt)
            XCTAssertEqual(word.reviewLogs.count, 1)
        }

        let relaunchedContext = ModelContext(container)
        let words = try relaunchedContext.fetch(FetchDescriptor<VocabularyWord>())
        let persisted = try XCTUnwrap(words.first { $0.id == wordID })
        XCTAssertEqual(persisted.progress?.state, .review)
        XCTAssertEqual(persisted.progress?.intervalDays, 20)
        XCTAssertEqual(persisted.progress?.dueAt, expectedDueAt)
        XCTAssertEqual(persisted.progress?.reviewCount, 5)
        XCTAssertEqual(persisted.reviewLogs.count, 1)
        XCTAssertEqual(persisted.reviewLogs.first?.rating, .good)
        let rebuilt = try StudyQueueService(calendar: calendar).buildSession(
            in: relaunchedContext,
            mode: .dueReviewsOnly,
            now: expectedDueAt,
            randomizesQueue: false
        )
        XCTAssertEqual(rebuilt.items.map(\.id), [wordID])
    }

    private func makeWord(
        _ japanese: String,
        state: LearningState,
        dueAt: Date,
        createdAt: Date
    ) -> VocabularyWord {
        let word = VocabularyWord(
            japanese: japanese,
            kana: japanese,
            chineseMeaning: japanese,
            jlptLevel: "N5",
            createdAt: createdAt,
            updatedAt: createdAt
        )
        word.progress = LearningProgress(
            state: state,
            dueAt: dueAt,
            createdAt: createdAt,
            updatedAt: createdAt,
            word: word
        )

        return word
    }

    private func makeViewModel(
        saveRatingChanges: ((ModelContext) throws -> Void)? = nil
    ) -> StudySessionViewModel {
        StudySessionViewModel(
            queueService: StudyQueueService(calendar: calendar),
            scheduler: DefaultReviewScheduler(calendar: calendar),
            saveRatingChanges: saveRatingChanges
        )
    }

    @discardableResult
    private func addFormalLog(
        to word: VocabularyWord,
        rating: ReviewRating,
        intervalDays: Int,
        reviewedAt: Date
    ) -> ReviewLog {
        let log = ReviewLog(
            reviewedAt: reviewedAt,
            rating: rating,
            previousState: .review,
            nextState: .review,
            previousIntervalDays: intervalDays,
            nextIntervalDays: intervalDays,
            scheduledDueAt: word.progress?.dueAt ?? reviewedAt,
            word: word
        )
        word.reviewLogs.append(log)
        return log
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0
    ) -> Date {
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )

        guard let date = components.date else {
            XCTFail("Invalid test date: \(components)")
            return Date(timeIntervalSinceReferenceDate: 0)
        }

        return date
    }

    private func addingMinutes(_ minutes: Int, to date: Date) -> Date {
        guard let result = calendar.date(byAdding: .minute, value: minutes, to: date) else {
            XCTFail("Failed to add minutes")
            return date
        }

        return result
    }
}
