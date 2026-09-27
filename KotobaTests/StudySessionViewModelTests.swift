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
