//
//  StudySessionViewModelTests.swift
//  KotobaTests
//
//  Created by Codex on 2026/6/16.
//

import SwiftData
import XCTest

@MainActor
final class StudySessionViewModelTests: XCTestCase {
    private var calendar: Calendar!
    private var speechService: SpySpeechService!
    private var viewModel: StudySessionViewModel!

    override func setUp() {
        super.setUp()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        self.calendar = calendar
        speechService = SpySpeechService()
        viewModel = StudySessionViewModel(
            queueService: StudyQueueService(calendar: calendar),
            scheduler: DefaultReviewScheduler(calendar: calendar),
            speechService: speechService
        )
        viewModel.updateSettings(
            speechRate: AppSettings.defaultJapaneseSpeechRate,
            autoSpeakWord: false,
            autoSpeakExample: false
        )
    }

    override func tearDown() {
        viewModel = nil
        speechService = nil
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
        viewModel.handleShortcut(.showAnswer, context: context, now: now)
        viewModel.handleShortcut(.rate(.good), context: context, now: now)

        XCTAssertEqual(first.reviewLogs.count, 1)
        XCTAssertEqual(first.progress?.state, .review)
        XCTAssertEqual(first.progress?.intervalDays, 2)
        XCTAssertEqual(viewModel.currentWord?.japanese, "確認")
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
        XCTAssertTrue(viewModel.isSpellingActive)
        XCTAssertEqual(viewModel.spellingWords.map(\.japanese), ["学生"])
    }

    func testCompletionEntersSpellingBeforeSummary() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        let word = makeWord("学生", state: .new, dueAt: now, createdAt: now)
        context.insert(word)
        try context.save()

        viewModel.loadSession(context: context, now: now)
        viewModel.handleShortcut(.showAnswer, context: context, now: now)
        viewModel.handleShortcut(.rate(.again), context: context, now: now)

        XCTAssertTrue(viewModel.isSpellingActive)
        XCTAssertNil(viewModel.summary)
        XCTAssertEqual(viewModel.spellingWords.map(\.japanese), ["学生"])

        viewModel.completeSpelling(
            .init(
                totalCount: 1,
                firstAttemptCorrectCount: 1,
                retryCorrectCount: 0,
                remainingIncorrectCount: 0
            )
        )

        XCTAssertEqual(viewModel.summary?.reviewedCount, 1)
        XCTAssertEqual(viewModel.summary?.newWordCount, 1)
        XCTAssertEqual(viewModel.summary?.lapseCount, 0)
        XCTAssertEqual(viewModel.summary?.spellingTotalCount, 1)
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

    func testSpeechShortcutsUseCurrentWordAndExample() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        let word = makeWord("学生", state: .new, dueAt: now, createdAt: now)
        word.exampleJapanese = "私は学生です。"
        context.insert(word)
        try context.save()

        viewModel.loadSession(context: context, now: now)
        viewModel.handleShortcut(.speakWord, context: context, now: now)
        XCTAssertEqual(viewModel.speechState, .speakingWord)

        viewModel.handleShortcut(.speakExample, context: context, now: now)
        XCTAssertEqual(viewModel.speechState, .speakingExample)

        viewModel.handleShortcut(.stopSpeech, context: context, now: now)
        XCTAssertEqual(viewModel.speechState, .idle)

        XCTAssertEqual(speechService.spokenWords, ["学生"])
        XCTAssertEqual(speechService.spokenExamples, ["私は学生です。"])
        XCTAssertEqual(speechService.stopCount, 1)
    }

    func testEmptyExampleIsNotSpoken() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        let word = makeWord("学生", state: .new, dueAt: now, createdAt: now)
        word.exampleJapanese = "   "
        context.insert(word)
        try context.save()

        viewModel.loadSession(context: context, now: now)
        viewModel.handleShortcut(.speakExample, context: context, now: now)

        XCTAssertEqual(speechService.spokenExamples, [])
        XCTAssertEqual(viewModel.speechState, .idle)
    }

    func testAdvancingToNextCardStopsCurrentSpeech() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        let first = makeWord("学生", state: .new, dueAt: now, createdAt: now)
        let second = makeWord("確認", state: .new, dueAt: now, createdAt: addingMinutes(1, to: now))
        context.insert(first)
        context.insert(second)
        try context.save()

        viewModel.loadSession(context: context, now: now)
        viewModel.handleShortcut(.speakWord, context: context, now: now)
        viewModel.handleShortcut(.showAnswer, context: context, now: now)
        viewModel.handleShortcut(.rate(.good), context: context, now: now)

        XCTAssertEqual(speechService.stopCount, 1)
        XCTAssertEqual(viewModel.speechState, .idle)
        XCTAssertEqual(viewModel.currentWord?.japanese, "確認")
    }

    func testAutoSpeakTriggersOnlyWhenCurrentWordChanges() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        let first = makeWord("学生", state: .new, dueAt: now, createdAt: now)
        let second = makeWord("確認", state: .new, dueAt: now, createdAt: addingMinutes(1, to: now))
        context.insert(first)
        context.insert(second)
        try context.save()

        viewModel.updateSettings(
            speechRate: AppSettings.defaultJapaneseSpeechRate,
            autoSpeakWord: true,
            autoSpeakExample: false
        )
        viewModel.loadSession(context: context, now: now)

        XCTAssertEqual(speechService.spokenWords, ["学生"])

        viewModel.handleShortcut(.showAnswer, context: context, now: now)
        viewModel.handleShortcut(.toggleFavorite, context: context, now: now)
        XCTAssertEqual(speechService.spokenWords, ["学生"])

        viewModel.handleShortcut(.rate(.good), context: context, now: now)
        XCTAssertEqual(speechService.spokenWords, ["学生", "確認"])
    }

    func testAutoSpeakDoesNotTriggerWhenDisabled() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = makeDate(year: 2026, month: 6, day: 16, hour: 9)
        context.insert(makeWord("学生", state: .new, dueAt: now, createdAt: now))
        try context.save()

        viewModel.updateSettings(
            speechRate: AppSettings.defaultJapaneseSpeechRate,
            autoSpeakWord: false,
            autoSpeakExample: false
        )
        viewModel.loadSession(context: context, now: now)

        XCTAssertEqual(speechService.spokenWords, [])
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

private final class SpySpeechService: SpeechServicing {
    var state: SpeechPlaybackState = .idle
    var speechRate: Float = Float(AppSettings.defaultJapaneseSpeechRate)
    var onStateChange: ((SpeechPlaybackState) -> Void)?

    private(set) var spokenWords: [String] = []
    private(set) var spokenExamples: [String] = []
    private(set) var stopCount = 0

    func speakWord(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }

        spokenWords.append(trimmedText)
        updateState(.speakingWord)
    }

    func speakExample(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }

        spokenExamples.append(trimmedText)
        updateState(.speakingExample)
    }

    func stop() {
        stopCount += 1
        updateState(.idle)
    }

    private func updateState(_ newState: SpeechPlaybackState) {
        state = newState
        onStateChange?(newState)
    }
}
