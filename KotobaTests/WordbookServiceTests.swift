//
//  WordbookServiceTests.swift
//  KotobaTests
//
//  Created by Codex on 2026/6/16.
//

import SwiftData
import XCTest

@MainActor
final class WordbookServiceTests: XCTestCase {
    private let service = WordbookService()

    func testSearchTrimsWhitespaceAndMatchesExpressionReadingAndMeaning() {
        let words = [
            makeWord(japanese: "勉強", kana: "べんきょう", chineseMeaning: "学习"),
            makeWord(japanese: "会社", kana: "かいしゃ", chineseMeaning: "公司"),
            makeWord(japanese: "静か", kana: "しずか", chineseMeaning: "安静")
        ]

        var filters = WordbookFilters(searchText: "  会社  ")
        XCTAssertEqual(service.filter(words, using: filters).map(\.japanese), ["会社"])

        filters.searchText = "しず"
        XCTAssertEqual(service.filter(words, using: filters).map(\.japanese), ["静か"])

        filters.searchText = "学习"
        XCTAssertEqual(service.filter(words, using: filters).map(\.japanese), ["勉強"])
    }

    func testFiltersByJLPTPartOfSpeechTagFavoriteAndLearningState() {
        let target = makeWord(
            japanese: "確認",
            kana: "かくにん",
            chineseMeaning: "确认",
            partOfSpeech: "名词",
            jlptLevel: "N3",
            tags: ["工作", "重点"],
            isFavorite: true,
            state: .review
        )
        let distractor = makeWord(
            japanese: "駅",
            kana: "えき",
            chineseMeaning: "车站",
            partOfSpeech: "名词",
            jlptLevel: "N5",
            tags: ["生活"],
            state: .new
        )

        let filters = WordbookFilters(
            jlptLevel: "N3",
            partOfSpeech: "名词",
            tag: "重点",
            learningState: LearningState.review.rawValue,
            favoritesOnly: true
        )

        XCTAssertEqual(service.filter([target, distractor], using: filters).map(\.japanese), ["確認"])
    }

    func testCreateWordValidatesRequiredFieldsAndCreatesProgress() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSinceReferenceDate: 100)

        XCTAssertThrowsError(try service.createWord(from: WordEditorDraft(), in: context, now: now)) { error in
            XCTAssertEqual(
                error as? WordbookValidationError,
                .missingRequiredFields(["日语单词", "假名", "中文释义"])
            )
        }

        var draft = WordEditorDraft()
        draft.expression = "  電車  "
        draft.reading = "  でんしゃ  "
        draft.meaningChinese = "  电车  "
        draft.partOfSpeech = "  名词  "
        draft.jlptLevel = " n5 "
        draft.tagsText = "交通; 生活;交通"

        let word = try service.createWord(from: draft, in: context, now: now)

        XCTAssertEqual(word.japanese, "電車")
        XCTAssertEqual(word.kana, "でんしゃ")
        XCTAssertEqual(word.chineseMeaning, "电车")
        XCTAssertEqual(word.partOfSpeech, "名词")
        XCTAssertEqual(word.jlptLevel, "N5")
        XCTAssertEqual(word.tags, ["交通", "生活"])
        XCTAssertEqual(word.progress?.state, .new)
        XCTAssertEqual(word.progress?.dueAt, now)
    }

    func testUpdateWordTrimsFieldsAndParsesTags() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let word = makeWord(japanese: "古い", kana: "ふるい", chineseMeaning: "旧的")
        context.insert(word)
        try context.save()

        var draft = WordEditorDraft(word: word)
        draft.expression = "  新しい "
        draft.reading = " あたらしい "
        draft.meaningChinese = " 新的 "
        draft.partOfSpeech = " 形容词 "
        draft.jlptLevel = " n5 "
        draft.tagsText = "常用; 形容词;常用"
        draft.isFavorite = true

        try service.updateWord(word, from: draft, in: context, now: Date(timeIntervalSinceReferenceDate: 200))

        XCTAssertEqual(word.japanese, "新しい")
        XCTAssertEqual(word.kana, "あたらしい")
        XCTAssertEqual(word.chineseMeaning, "新的")
        XCTAssertEqual(word.partOfSpeech, "形容词")
        XCTAssertEqual(word.jlptLevel, "N5")
        XCTAssertEqual(word.tags, ["常用", "形容词"])
        XCTAssertTrue(word.isFavorite)
    }

    func testResetProgressClearsReviewLogsAndReturnsToNew() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSinceReferenceDate: 300)
        let word = makeWord(japanese: "便利", kana: "べんり", chineseMeaning: "方便", state: .review)
        word.progress?.intervalDays = 12
        word.progress?.reviewCount = 5
        word.progress?.lapseCount = 2
        word.progress?.lastReviewedAt = now.addingTimeInterval(-86_400)
        word.reviewLogs = [makeReviewLog(word: word, now: now)]

        context.insert(word)
        try context.save()

        try service.resetProgress(for: word, in: context, now: now)

        XCTAssertEqual(word.progress?.state, .new)
        XCTAssertEqual(word.progress?.intervalDays, 0)
        XCTAssertEqual(word.progress?.reviewCount, 0)
        XCTAssertEqual(word.progress?.lapseCount, 0)
        XCTAssertNil(word.progress?.lastReviewedAt)
        XCTAssertEqual(word.progress?.dueAt, now)
        XCTAssertTrue(word.reviewLogs.isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ReviewLog>()).count, 0)
    }

    func testDeleteWordCascadesProgressAndReviewLogs() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSinceReferenceDate: 400)
        let word = makeWord(japanese: "説明", kana: "せつめい", chineseMeaning: "说明", state: .review)
        word.reviewLogs = [makeReviewLog(word: word, now: now)]

        context.insert(word)
        try context.save()

        try service.deleteWord(word, in: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<VocabularyWord>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LearningProgress>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ReviewLog>()).count, 0)
    }

    private func makeWord(
        japanese: String,
        kana: String,
        chineseMeaning: String,
        partOfSpeech: String = "名词",
        jlptLevel: String = "N5",
        tags: [String] = [],
        isFavorite: Bool = false,
        state: LearningState = .new
    ) -> VocabularyWord {
        let word = VocabularyWord(
            japanese: japanese,
            kana: kana,
            chineseMeaning: chineseMeaning,
            partOfSpeech: partOfSpeech,
            jlptLevel: jlptLevel,
            tags: tags,
            isFavorite: isFavorite
        )
        word.progress = LearningProgress(state: state, word: word)
        return word
    }

    private func makeReviewLog(word: VocabularyWord, now: Date) -> ReviewLog {
        ReviewLog(
            reviewedAt: now,
            rating: .good,
            previousState: .learning,
            nextState: .review,
            previousIntervalDays: 1,
            nextIntervalDays: 3,
            scheduledDueAt: now.addingTimeInterval(3 * 86_400),
            word: word
        )
    }
}
