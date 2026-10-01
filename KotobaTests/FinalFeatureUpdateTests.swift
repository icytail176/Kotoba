import SwiftData
import XCTest
@testable import Kotoba

@MainActor
final class FinalFeatureUpdateTests: XCTestCase {
    private struct ExpectedFailure: Error {}

    func testKeyboardHelpUsesSharedReferenceData() {
        XCTAssertFalse(KeyboardShortcutReference.sections.isEmpty)
        XCTAssertTrue(KeyboardShortcutReference.sections.contains { section in
            section.items.contains { $0.action == "显示答案" && $0.keys == "Space" }
        })
    }

    func testReviewHistoryFetchIsWordScopedLimitedAndDescending() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let target = makeWord(expression: "対象", reading: "たいしょう")
        let other = makeWord(expression: "別", reading: "べつ")
        context.insert(target)
        context.insert(other)

        for offset in 0..<12 {
            let log = makeLog(
                word: target,
                reviewedAt: Date(timeIntervalSinceReferenceDate: Double(offset)),
                rating: .good,
                previousState: .review,
                nextState: .review,
                previousIntervalDays: offset + 1,
                nextIntervalDays: offset + 2
            )
            context.insert(log)
        }
        context.insert(makeLog(word: other, reviewedAt: Date(timeIntervalSinceReferenceDate: 100)))
        try context.save()

        let service = WordbookService()
        let recent = try service.fetchReviewLogs(for: target.id, in: context)
        XCTAssertEqual(recent.logs.count, 10)
        XCTAssertEqual(recent.totalCount, 12)
        XCTAssertEqual(recent.logs.map(\.reviewedAt), recent.logs.map(\.reviewedAt).sorted(by: >))
        XCTAssertTrue(recent.logs.allSatisfy { $0.word?.id == target.id })

        let all = try service.fetchReviewLogs(for: target.id, in: context, limit: nil)
        XCTAssertEqual(all.logs.count, 12)
        XCTAssertEqual(all.totalCount, 12)

        let empty = try service.fetchReviewLogs(for: UUID(), in: context)
        XCTAssertTrue(empty.logs.isEmpty)
        XCTAssertEqual(empty.totalCount, 0)
    }

    func testReviewHistoryPresentationPreservesRatingAndMasterySemantics() {
        let word = makeWord(expression: "語", reading: "ご")
        let cases: [(ReviewRating, String)] = [
            (.again, "忘记"),
            (.hard, "模糊"),
            (.good, "认识"),
            (.easy, "熟练")
        ]

        for (rating, expected) in cases {
            let log = makeLog(word: word, rating: rating)
            XCTAssertEqual(WordReviewHistoryPresentation.makeRow(from: log).ratingText, expected)
        }

        let automatic = makeLog(
            word: word,
            rating: .good,
            previousState: .review,
            nextState: .suspended,
            previousIntervalDays: 60,
            nextIntervalDays: 0
        )
        let automaticRow = WordReviewHistoryPresentation.makeRow(from: automatic)
        XCTAssertEqual(automaticRow.ratingText, "认识")
        XCTAssertEqual(automaticRow.transitionText, "60 天 → 已熟练")

        let manual = makeLog(
            word: word,
            rating: .easy,
            previousState: .review,
            nextState: .suspended,
            previousIntervalDays: 32,
            nextIntervalDays: 0
        )
        XCTAssertEqual(WordReviewHistoryPresentation.makeRow(from: manual).ratingText, "熟练")
        XCTAssertEqual(WordReviewHistoryPresentation.makeRow(from: manual).transitionText, "32 天 → 已熟练")

        let lapse = makeLog(
            word: word,
            rating: .again,
            previousState: .review,
            nextState: .relearning,
            previousIntervalDays: 12,
            nextIntervalDays: 0
        )
        XCTAssertEqual(WordReviewHistoryPresentation.makeRow(from: lapse).transitionText, "复习 → 重新学习")

        let newProgress = LearningProgress(state: .new)
        XCTAssertFalse(WordDetailLearningPresentation.canResetToUnlearned(progress: newProgress, reviewLogCount: 0))
        XCTAssertTrue(WordDetailLearningPresentation.canResetToUnlearned(progress: newProgress, reviewLogCount: 1))
        XCTAssertTrue(WordDetailLearningPresentation.canResetToUnlearned(progress: LearningProgress(state: .review), reviewLogCount: 0))
    }

    func testWordbookProgressCountsCanonicalBucketsAndExcludesArchived() async throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let book = WordBook(name: "测试")
        context.insert(book)

        let missing = makeWord(expression: "未建进度", reading: "みけん", book: book, state: nil)
        let new = makeWord(expression: "新", reading: "しん", book: book, state: .new)
        let learning = makeWord(expression: "学习", reading: "がくしゅう", book: book, state: .learning)
        let relearning = makeWord(expression: "重学", reading: "じゅうがく", book: book, state: .relearning)
        let review = makeWord(expression: "复习", reading: "ふくしゅう", book: book, state: .review)
        let mastered = makeWord(expression: "熟练", reading: "じゅくれん", book: book, state: .suspended)
        let archived = makeWord(expression: "归档", reading: "きとう", book: book, state: .review)
        archived.isArchived = true
        for word in [missing, new, learning, relearning, review, mastered, archived] {
            context.insert(word)
        }
        try context.save()

        let counts = try await WordBookService().summaryCounts(
            in: container,
            wordBookID: book.id,
            now: Date()
        )
        XCTAssertEqual(counts.totalWordCount, 6)
        XCTAssertEqual(counts.newWordCount, 2)
        XCTAssertEqual(counts.startedWordCount, 4)
        XCTAssertEqual(counts.reviewingWordCount, 3)
        XCTAssertEqual(counts.masteredWordCount, 1)

        var filters = WordbookFilters()
        filters.searchText = "不存在"
        filters.status = .difficult
        let page = try WordbookService().fetchWordPage(
            in: context,
            scopedWordBookID: book.id,
            filters: filters,
            offset: 0,
            limit: 50
        )
        XCTAssertEqual(page.matchingCount, 0)
        let unchanged = try await WordBookService().summaryCounts(in: container, wordBookID: book.id)
        XCTAssertEqual(unchanged, counts)
    }

    func testWordbookSortOptionsAreDeterministicAndComposeWithSearchAndFilter() throws {
        let service = WordbookService()
        let base = Date(timeIntervalSinceReferenceDate: 10_000)
        let recent = makeWord(expression: "最近", reading: "さいきん", state: .review)
        recent.progress?.lastReviewedAt = base.addingTimeInterval(30)
        recent.progress?.dueAt = base.addingTimeInterval(300)
        recent.progress?.lapseCount = 1
        let overdue = makeWord(expression: "対象早", reading: "たいしょうはやい", state: .review)
        overdue.progress?.lastReviewedAt = base.addingTimeInterval(10)
        overdue.progress?.dueAt = base.addingTimeInterval(100)
        overdue.progress?.lapseCount = 4
        let later = makeWord(expression: "対象遅", reading: "たいしょうおそい", state: .learning)
        later.progress?.lastReviewedAt = base.addingTimeInterval(20)
        later.progress?.dueAt = base.addingTimeInterval(200)
        later.progress?.lapseCount = 2
        let unlearned = makeWord(expression: "未学习", reading: "みがくしゅう", state: .new)

        XCTAssertEqual(service.sorted([overdue, unlearned, recent, later], by: .recentlyStudied).map(\.id), [recent.id, later.id, overdue.id, unlearned.id])
        XCTAssertEqual(service.sorted([recent, unlearned, later, overdue], by: .nextDue).map(\.id), [overdue.id, later.id, recent.id, unlearned.id])
        XCTAssertEqual(service.sorted([recent, unlearned, later, overdue], by: .lapseCount).map(\.id), [overdue.id, later.id, recent.id, unlearned.id])

        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let book = WordBook(name: "组合")
        context.insert(book)
        for word in [recent, overdue, later, unlearned] {
            word.wordBook = book
            context.insert(word)
        }
        try context.save()

        var filters = WordbookFilters()
        filters.searchText = "対象"
        filters.status = .difficult
        filters.sort = .lapseCount
        let page = try service.fetchWordPage(
            in: context,
            scopedWordBookID: book.id,
            filters: filters,
            offset: 0,
            limit: 50
        )
        XCTAssertEqual(page.rows.map(\.id), [overdue.id, later.id])
        XCTAssertEqual(filters.searchText, "対象")
        XCTAssertEqual(filters.status, .difficult)
        XCTAssertEqual(filters.sort, .lapseCount)
    }

    func testResetToUnlearnedPreservesIdentityFavoriteAndMetadataThenReentersQueue() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSinceReferenceDate: 50_000)
        let word = makeWord(expression: "確認", reading: "かくにん", state: .suspended)
        word.isFavorite = true
        word.progress?.intervalDays = 60
        word.progress?.reviewCount = 8
        word.progress?.lapseCount = 3
        word.progress?.lastReviewedAt = now.addingTimeInterval(-100)
        let originalID = word.id
        let originalExpression = word.japanese
        let logs = [
            makeLog(word: word, reviewedAt: now.addingTimeInterval(-300), rating: .again),
            makeLog(word: word, reviewedAt: now.addingTimeInterval(-200), rating: .hard),
            makeLog(word: word, reviewedAt: now.addingTimeInterval(-100), rating: .good),
            makeLog(word: word, reviewedAt: now, rating: .good, previousState: .review, nextState: .suspended, previousIntervalDays: 60)
        ]
        context.insert(word)
        logs.forEach(context.insert)
        try context.save()

        try WordbookService().resetProgress(for: word, in: context, now: now.addingTimeInterval(10))

        XCTAssertEqual(word.id, originalID)
        XCTAssertEqual(word.japanese, originalExpression)
        XCTAssertTrue(word.isFavorite)
        XCTAssertEqual(word.progress?.state, .new)
        XCTAssertEqual(word.progress?.intervalDays, 0)
        XCTAssertEqual(word.progress?.reviewCount, 0)
        XCTAssertEqual(word.progress?.lapseCount, 0)
        XCTAssertNil(word.progress?.lastReviewedAt)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReviewLog>()), 0)
        XCTAssertTrue(word.reviewLogs.isEmpty)

        let session = try StudyQueueService(shuffle: { $0 }).buildSession(
            in: context,
            mode: .newWordsOnly,
            now: now.addingTimeInterval(20),
            randomizesQueue: false
        )
        XCTAssertTrue(session.items.contains { $0.id == originalID && $0.kind == .newWord })
    }

    func testResetFailureRollsBackProgressLogsAndFavoriteThenRetrySucceeds() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let word = makeWord(expression: "失敗", reading: "しっぱい", state: .review)
        word.isFavorite = true
        word.progress?.intervalDays = 12
        word.progress?.reviewCount = 4
        word.progress?.lapseCount = 2
        let log = makeLog(word: word, rating: .good, previousIntervalDays: 6, nextIntervalDays: 12)
        context.insert(word)
        context.insert(log)
        try context.save()

        var saveAttempts = 0
        let service = WordbookService(saveChanges: { context in
            saveAttempts += 1
            if saveAttempts == 1 { throw ExpectedFailure() }
            try context.save()
        })

        XCTAssertThrowsError(try service.resetProgress(for: word, in: context))
        XCTAssertEqual(word.progress?.state, .review)
        XCTAssertEqual(word.progress?.intervalDays, 12)
        XCTAssertEqual(word.progress?.reviewCount, 4)
        XCTAssertEqual(word.progress?.lapseCount, 2)
        XCTAssertTrue(word.isFavorite)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReviewLog>()), 1)

        try service.resetProgress(for: word, in: context)
        XCTAssertEqual(saveAttempts, 2)
        XCTAssertEqual(word.progress?.state, .new)
        XCTAssertTrue(word.isFavorite)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReviewLog>()), 0)
        XCTAssertTrue(word.reviewLogs.isEmpty)
    }

    func testResetRemovesOnlyTargetHistoryFromStatisticsInput() async throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let target = makeWord(expression: "対象", reading: "たいしょう", state: .review)
        let other = makeWord(expression: "他", reading: "ほか", state: .review)
        context.insert(target)
        context.insert(other)
        context.insert(makeLog(word: target, rating: .good))
        let otherLog = makeLog(word: other, rating: .hard)
        context.insert(otherLog)
        try context.save()

        let before = try await StudyStatisticsService().makeInput(in: container)
        XCTAssertEqual(before.logs.count, 2)

        try WordbookService().resetProgress(for: target, in: context)
        let after = try await StudyStatisticsService().makeInput(in: container)
        XCTAssertEqual(after.logs.map(\.id), [otherLog.id])
        XCTAssertEqual(other.progress?.state, .review)
    }

    func testRomajiSyllabicNApostropheRulesAndRegressions() {
        let expected: [(String, String)] = [
            ("かたかな", "katakana"), ("カタカナ", "katakana"), ("かな", "kana"),
            ("な", "na"), ("なな", "nana"), ("にほん", "nihon"),
            ("テレビ", "terebi"), ("アルバイト", "arubaito"),
            ("ほんや", "hon'ya"), ("しんよう", "shin'yō"),
            ("んあ", "n'a"), ("んい", "n'i"), ("んう", "n'u"),
            ("んえ", "n'e"), ("んお", "n'o"),
            ("んや", "n'ya"), ("んゆ", "n'yu"), ("んよ", "n'yo"),
            ("ンア", "n'a"), ("ンヤ", "n'ya"),
            ("にゃ", "nya"), ("きゃ", "kya"), ("しゃ", "sha"), ("ちゃ", "cha"),
            ("がっこう", "gakkō"), ("コンピューター", "konpyūtā")
        ]
        for (reading, romaji) in expected {
            XCTAssertEqual(JapaneseRomajiFormatter.string(from: reading), romaji, reading)
        }
    }

    func testRomajiSearchMatchesSyntheticKatakanaReading() throws {
        let word = makeWord(expression: "片仮名", reading: "カタカナ", state: .new)
        var filters = WordbookFilters()
        filters.wordBookID = WordbookFilterValue.all.rawValue
        filters.searchText = "katakana"
        XCTAssertEqual(WordbookService().filter([word], using: filters, currentWordBookID: nil).map(\.id), [word.id])
    }

    func testAllBundledReadingsHaveOnlyKanaSourcedApostrophes() throws {
        let resourceDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Kotoba/Resources")
        let parser = CSVParser()
        var readingCount = 0
        var apostropheCount = 0

        for definition in BuiltInWordBookDefinition.all {
            let text = try String(
                contentsOf: resourceDirectory.appendingPathComponent(definition.fileName),
                encoding: .utf8
            )
            let table = try parser.parse(text)
            for row in table.rows {
                let reading = row.fields[1]
                let first = JapaneseRomajiFormatter.string(from: reading)
                let second = JapaneseRomajiFormatter.string(from: reading)
                XCTAssertFalse(first.isEmpty, "\(definition.fileName):\(row.lineNumber)")
                XCTAssertEqual(first, second, "\(definition.fileName):\(row.lineNumber)")

                let actual = first.filter { $0 == "'" }.count
                let expected = expectedSyllabicNApostropheCount(in: reading)
                XCTAssertEqual(actual, expected, "\(definition.fileName):\(row.lineNumber) \(reading) → \(first)")
                readingCount += 1
                apostropheCount += actual
            }
        }

        XCTAssertEqual(readingCount, 10_609)
        print("ROMAJI_APOSTROPHE_AUDIT_COUNT=\(apostropheCount)")
    }

    private func makeWord(
        expression: String,
        reading: String,
        book: WordBook? = nil,
        state: LearningState? = .new
    ) -> VocabularyWord {
        let word = VocabularyWord(
            japanese: expression,
            kana: reading,
            chineseMeaning: "释义",
            jlptLevel: "N5",
            wordBook: book
        )
        if let state {
            word.progress = LearningProgress(state: state, word: word)
        }
        return word
    }

    private func makeLog(
        word: VocabularyWord,
        reviewedAt: Date = Date(timeIntervalSinceReferenceDate: 1_000),
        rating: ReviewRating = .good,
        previousState: LearningState = .review,
        nextState: LearningState = .review,
        previousIntervalDays: Int = 2,
        nextIntervalDays: Int = 4
    ) -> ReviewLog {
        ReviewLog(
            reviewedAt: reviewedAt,
            rating: rating,
            previousState: previousState,
            nextState: nextState,
            previousIntervalDays: previousIntervalDays,
            nextIntervalDays: nextIntervalDays,
            scheduledDueAt: reviewedAt,
            word: word
        )
    }

    private func expectedSyllabicNApostropheCount(in reading: String) -> Int {
        let normalized = reading.precomposedStringWithCanonicalMapping
        let hiragana = normalized.unicodeScalars.map { scalar -> Character in
            let code = scalar.value
            if (0x30A1...0x30F6).contains(code), let converted = UnicodeScalar(code - 0x60) {
                return Character(String(converted))
            }
            return Character(String(scalar))
        }
        let disambiguatingFollowers = Set("あいうえおやゆよぁぃぅぇぉゃゅょ")
        guard hiragana.count > 1 else { return 0 }
        return hiragana.indices.dropLast().filter { index in
            hiragana[index] == "ん" && disambiguatingFollowers.contains(hiragana[hiragana.index(after: index)])
        }.count
    }
}
