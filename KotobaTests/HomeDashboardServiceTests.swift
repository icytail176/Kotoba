//
//  HomeDashboardServiceTests.swift
//  KotobaTests
//
//  Created by Codex on 2026/6/17.
//

import SwiftData
import XCTest
@testable import Kotoba

@MainActor
final class HomeDashboardServiceTests: XCTestCase {
    func testDashboardStateLabelsUseReviewForReviewCountAndSuspendedForMasteredCount() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let book = WordBook(name: "状态语义")
        context.insert(book)

        for (index, state) in LearningState.allCases.enumerated() {
            let word = makeWord(
                "状态\(index)",
                exampleJapanese: "例句",
                exampleChinese: "例句",
                wordBook: book
            )
            word.progress?.state = state
            if state == .suspended {
                word.reviewLogs = [ReviewLog(
                    rating: .good,
                    previousState: .review,
                    nextState: .suspended,
                    previousIntervalDays: 60,
                    nextIntervalDays: 0,
                    scheduledDueAt: Date(),
                    word: word
                )]
            }
            context.insert(word)
        }
        try context.save()

        let snapshot = try HomeDashboardService().makeSnapshot(
            in: context,
            selectedIDString: book.id.uuidString
        ).snapshot

        XCTAssertEqual(snapshot.totalWordCount, LearningState.allCases.count)
        XCTAssertEqual(snapshot.remainingNewWordCount, 1)
        XCTAssertEqual(snapshot.reviewingWordCount, 3)
        XCTAssertEqual(snapshot.masteredWordCount, 1, "自动熟练的 suspended 词只计入已熟练")
        XCTAssertEqual(snapshot.dueReviewCount, 3, "当前待复习只包含 StudyDuePolicy 判定为到期的 active learned words")
    }

    func testSevenDayForecastUsesCalendarDaysAcrossDSTAndExcludesIneligibleStates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 3, day: 7, hour: 15
        )))

        func date(offset: Int, hour: Int = 9) throws -> Date {
            let day = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)))
            return try XCTUnwrap(calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day))
        }

        func forecastWord(_ expression: String, state: LearningState, offset: Int, archived: Bool = false) throws -> VocabularyWord {
            let word = VocabularyWord(japanese: expression, kana: expression, chineseMeaning: expression, jlptLevel: "N5")
            word.isArchived = archived
            word.progress = LearningProgress(state: state, dueAt: try date(offset: offset), word: word)
            return word
        }

        let words = try [
            forecastWord("逾期", state: .review, offset: -2),
            forecastWord("今天", state: .learning, offset: 0, archived: false),
            forecastWord("明天", state: .relearning, offset: 1),
            forecastWord("后天", state: .review, offset: 2),
            forecastWord("第六天", state: .review, offset: 6),
            forecastWord("第七天", state: .review, offset: 7),
            forecastWord("新词", state: .new, offset: 1),
            forecastWord("熟练", state: .suspended, offset: 1),
            forecastWord("归档", state: .review, offset: 1, archived: true)
        ]

        let forecast = HomeDashboardService.reviewForecast(words: words, now: now, calendar: calendar)

        XCTAssertEqual(forecast.count, 7)
        XCTAssertEqual(forecast.map(\.reviewCount), [2, 1, 1, 0, 0, 0, 1])
        XCTAssertEqual(
            calendar.dateComponents([.day], from: forecast[0].day, to: forecast[1].day).day,
            1,
            "DST 边界必须按 Calendar 自然日递增"
        )
    }

    func testSevenDayForecastUsesOrdinaryCalendarWeek() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 30, hour: 16
        )))
        let today = calendar.startOfDay(for: now)
        let word = VocabularyWord(japanese: "予定", kana: "よてい", chineseMeaning: "预定", jlptLevel: "N4")
        word.progress = LearningProgress(
            state: .review,
            dueAt: try XCTUnwrap(calendar.date(byAdding: .day, value: 4, to: today)),
            word: word
        )

        let forecast = HomeDashboardService.reviewForecast(words: [word], now: now, calendar: calendar)

        XCTAssertEqual(forecast.map(\.reviewCount), [0, 0, 0, 0, 1, 0, 0])
        XCTAssertTrue(forecast.allSatisfy { calendar.startOfDay(for: $0.day) == $0.day })
    }

    func testRandomExampleUsesOnlySelectedWordBookAndRequiresBothExamples() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let selectedBook = WordBook(name: "当前词书")
        let otherBook = WordBook(name: "其他词书")
        let selectedWord = makeWord(
            "努力",
            exampleJapanese: "毎日の努力が大切です。",
            exampleChinese: "每天的努力很重要。",
            wordBook: selectedBook
        )
        let incompleteWord = makeWord(
            "水",
            exampleJapanese: "水を飲みます。",
            exampleChinese: "",
            wordBook: selectedBook
        )
        let otherWord = makeWord(
            "影響",
            exampleJapanese: "影響があります。",
            exampleChinese: "有影响。",
            wordBook: otherBook
        )

        context.insert(selectedBook)
        context.insert(otherBook)
        context.insert(selectedWord)
        context.insert(incompleteWord)
        context.insert(otherWord)
        try context.save()

        let service = HomeDashboardService()
        let result = try service.makeSnapshot(
            in: context,
            selectedIDString: selectedBook.id.uuidString
        )

        XCTAssertEqual(result.snapshot.example?.wordID, selectedWord.id)
        XCTAssertEqual(result.snapshot.example?.expression, "努力")
    }

    func testSnapshotShowsAllRemainingNewWordsAfterFormerDailyLimitIsExceeded() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let book = WordBook(name: "无限学习词书")
        let now = Date(timeIntervalSinceReferenceDate: 900_000_000)
        context.insert(book)

        for index in 0..<25 {
            let word = makeWord(
                "已学\(index)",
                exampleJapanese: "例句",
                exampleChinese: "例句",
                wordBook: book
            )
            word.progress?.state = .review
            word.progress?.dueAt = now.addingTimeInterval(2 * 86_400)
            word.reviewLogs = [
                ReviewLog(
                    reviewedAt: now,
                    rating: .good,
                    previousState: .new,
                    nextState: .review,
                    previousIntervalDays: 0,
                    nextIntervalDays: 2,
                    scheduledDueAt: now.addingTimeInterval(2 * 86_400),
                    word: word
                )
            ]
            context.insert(word)
        }

        for index in 0..<7 {
            context.insert(makeWord(
                "剩余\(index)",
                exampleJapanese: "例句",
                exampleChinese: "例句",
                wordBook: book
            ))
        }
        try context.save()

        let result = try HomeDashboardService().makeSnapshot(
            in: context,
            selectedIDString: book.id.uuidString,
            now: now
        )

        XCTAssertEqual(result.snapshot.remainingNewWordCount, 7)
    }

    func testHighlightingMarksAllTargetMatchesAndSurvivesMissingTarget() {
        let service = ExampleHighlightingService()

        let segments = service.segments(in: "努力と努力が必要です。", target: "努力")
        XCTAssertEqual(segments.filter(\.isHighlighted).map(\.text), ["努力", "努力"])
        XCTAssertEqual(segments.map(\.text).joined(), "努力と努力が必要です。")

        let missing = service.segments(in: "毎日続けます。", target: "努力")
        XCTAssertEqual(missing, [HighlightedTextSegment(text: "毎日続けます。", isHighlighted: false)])
    }

    func testDashboardQueueAndWordbookSummaryShareDuePolicy() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 9))!
        let laterToday = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now)!
        let book = WordBook(name: "到期口径")
        let review = makeWord("復習", exampleJapanese: "例句", exampleChinese: "例句", wordBook: book)
        review.progress?.state = .review
        review.progress?.dueAt = laterToday
        let learning = makeWord("学習", exampleJapanese: "例句", exampleChinese: "例句", wordBook: book)
        learning.progress?.state = .learning
        learning.progress?.dueAt = laterToday
        context.insert(book)
        context.insert(review)
        context.insert(learning)
        try context.save()

        let dashboard = try HomeDashboardService().makeSnapshot(
            in: context,
            selectedIDString: book.id.uuidString,
            now: now
        ).snapshot
        let queue = try StudyQueueService(calendar: calendar).buildSession(
            in: context,
            wordBook: book,
            mode: .dueReviewsOnly,
            now: now,
            randomizesQueue: false
        )
        let summary = WordBookService().summary(for: book, selectedID: book.id, now: now)

        XCTAssertEqual(dashboard.dueReviewCount, 1)
        XCTAssertEqual(queue.items.map(\.id), [review.id])
        XCTAssertEqual(summary.dueReviewCount, 1)
    }

    func testArchivedBuiltInWordsAreExcludedFromHomeQueueAndSearch() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSinceReferenceDate: 900_000_000)
        let book = WordBook(name: "JLPT N5", isBuiltIn: true)
        let activeNew = makeWord(
            "学生",
            exampleJapanese: "学生です。",
            exampleChinese: "是学生。",
            wordBook: book
        )
        let activeReview = makeWord(
            "復習",
            exampleJapanese: "復習します。",
            exampleChinese: "复习。",
            wordBook: book
        )
        activeReview.progress?.state = .review
        activeReview.progress?.dueAt = now.addingTimeInterval(-60)
        let archivedNew = makeWord(
            "归档新词",
            exampleJapanese: "例句。",
            exampleChinese: "例句。",
            wordBook: book
        )
        archivedNew.isArchived = true
        let archivedReview = makeWord(
            "归档复习词",
            exampleJapanese: "例句。",
            exampleChinese: "例句。",
            wordBook: book
        )
        archivedReview.isArchived = true
        archivedReview.progress?.state = .review
        archivedReview.progress?.dueAt = now.addingTimeInterval(-60)

        context.insert(book)
        [activeNew, activeReview, archivedNew, archivedReview].forEach { context.insert($0) }
        try context.save()

        let dashboard = try HomeDashboardService().makeSnapshot(
            in: context,
            selectedIDString: book.id.uuidString,
            now: now
        ).snapshot
        let queue = try StudyQueueService().buildSession(
            in: context,
            wordBook: book,
            now: now,
            randomizesQueue: false
        )
        let archivedSearch = try HomeSearchService().suggestions(
            in: context,
            query: "归档",
            currentWordBookID: book.id
        )

        XCTAssertEqual(dashboard.totalWordCount, 2)
        XCTAssertEqual(dashboard.remainingNewWordCount, 1)
        XCTAssertEqual(dashboard.dueReviewCount, 1)
        XCTAssertEqual(Set(queue.items.map(\.id)), Set([activeNew.id, activeReview.id]))
        XCTAssertTrue(archivedSearch.isEmpty)
    }

    func testDashboardWordbookAndStudyStatisticsAreReadOnly() async throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSinceReferenceDate: 900_000_000)
        let book = WordBook(name: "只读统计")
        let word = makeWord(
            "確認",
            exampleJapanese: "内容を確認します。",
            exampleChinese: "确认内容。",
            wordBook: book
        )
        word.progress?.state = .review
        word.progress?.intervalDays = 12
        word.progress?.reviewCount = 4
        word.progress?.lapseCount = 1
        word.progress?.dueAt = now.addingTimeInterval(86_400)
        word.progress?.lastReviewedAt = now.addingTimeInterval(-86_400)
        let log = ReviewLog(
            reviewedAt: now.addingTimeInterval(-86_400),
            rating: .good,
            previousState: .learning,
            nextState: .review,
            previousIntervalDays: 0,
            nextIntervalDays: 12,
            scheduledDueAt: word.progress?.dueAt ?? now,
            word: word
        )
        word.reviewLogs.append(log)
        context.insert(book)
        context.insert(word)
        context.insert(log)
        try context.save()

        let progressID = try XCTUnwrap(word.progress?.id)
        let originalDueAt = try XCTUnwrap(word.progress?.dueAt)
        let originalUpdatedAt = word.progress?.updatedAt

        _ = try HomeDashboardService().makeSnapshot(
            in: context,
            selectedIDString: book.id.uuidString,
            now: now
        )
        _ = WordBookService().summary(for: book, selectedID: book.id, now: now)
        let statisticsInput = try await StudyStatisticsService().makeSnapshot(in: container).input
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        _ = StudyStatisticsCalculator().calculate(
            input: statisticsInput,
            calendar: calendar,
            now: now,
            range: .sevenDays
        )
        _ = StudyStatisticsCalculator().calculate(
            input: statisticsInput,
            calendar: calendar,
            now: now,
            range: .thirtyDays
        )

        let progresses = try context.fetch(FetchDescriptor<LearningProgress>())
        let logs = try context.fetch(FetchDescriptor<ReviewLog>())
        XCTAssertEqual(progresses.count, 1)
        XCTAssertEqual(progresses.first?.id, progressID)
        XCTAssertEqual(progresses.first?.state, .review)
        XCTAssertEqual(progresses.first?.intervalDays, 12)
        XCTAssertEqual(progresses.first?.reviewCount, 4)
        XCTAssertEqual(progresses.first?.lapseCount, 1)
        XCTAssertEqual(progresses.first?.dueAt, originalDueAt)
        XCTAssertEqual(progresses.first?.updatedAt, originalUpdatedAt)
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.id, log.id)
    }

    private func makeWord(
        _ expression: String,
        exampleJapanese: String,
        exampleChinese: String,
        wordBook: WordBook
    ) -> VocabularyWord {
        let word = VocabularyWord(
            japanese: expression,
            kana: expression,
            chineseMeaning: expression,
            jlptLevel: "N5",
            exampleJapanese: exampleJapanese,
            exampleChinese: exampleChinese,
            wordBook: wordBook
        )
        word.progress = LearningProgress(state: .new, word: word)
        return word
    }
}
