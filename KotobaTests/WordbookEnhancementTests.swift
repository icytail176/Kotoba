import SwiftData
import XCTest
@testable import Kotoba

@MainActor
final class WordbookEnhancementTests: XCTestCase {
    private let service = WordbookService()

    func testSearchNormalizesAndMatchesAllSupportedFields() {
        let word = makeWord(
            "テレビ",
            reading: "てれび",
            meaning: "电视机",
            state: .review,
            sourceTerm: "Television"
        )

        for query in ["テレビ", "てれ", "电视", "  TELEVISION  ", "TEREBI"] {
            var filters = allFilters()
            filters.searchText = query
            XCTAssertEqual(service.filter([word], using: filters, currentWordBookID: nil).map(\.id), [word.id])
        }

        var noResult = allFilters()
        noResult.searchText = "radio"
        XCTAssertTrue(service.filter([word], using: noResult, currentWordBookID: nil).isEmpty)
    }

    func testStatusFiltersCombineLearningStatesAndExcludeArchivedWords() {
        let newWithoutProgress = makeWord("零", state: nil)
        let new = makeWord("新", state: .new)
        let learning = makeWord("学", state: .learning)
        let relearning = makeWord("再", state: .relearning)
        let review = makeWord("復", state: .review)
        let mastered = makeWord("熟", state: .suspended)
        let favorite = makeWord("星", state: .review, favorite: true)
        let difficult = makeWord("難", state: .suspended, lapseCount: 3)
        let archived = makeWord("旧", state: .review, favorite: true, lapseCount: 5)
        archived.isArchived = true
        let words = [newWithoutProgress, new, learning, relearning, review, mastered, favorite, difficult, archived]

        XCTAssertEqual(ids(for: .all, words: words).count, 8)
        XCTAssertEqual(ids(for: .new, words: words), Set([newWithoutProgress.id, new.id]))
        XCTAssertEqual(ids(for: .review, words: words), Set([learning.id, relearning.id, review.id, favorite.id]))
        XCTAssertEqual(ids(for: .mastered, words: words), Set([mastered.id, difficult.id]))
        XCTAssertEqual(ids(for: .favorite, words: words), Set([favorite.id]))
        XCTAssertEqual(ids(for: .difficult, words: words), Set([difficult.id]))
    }

    func testDifficultBoundaryAndSearchFilterComposition() {
        let lapseZero = makeWord("零", reading: "ぜろ", state: .review, lapseCount: 0)
        let lapseOne = makeWord("一", reading: "いち", state: .review, lapseCount: 1)
        let lapseTwo = makeWord("二", reading: "に", state: .review, lapseCount: 2)
        let lapseFive = makeWord("五", reading: "ご", state: .review, lapseCount: 5)
        let suspended = makeWord("熟二", reading: "に", state: .suspended, lapseCount: 3)

        var filters = allFilters()
        filters.status = .difficult
        filters.searchText = "に"
        let result = service.filter(
            [lapseZero, lapseOne, lapseTwo, lapseFive, suspended],
            using: filters,
            currentWordBookID: nil
        )

        XCTAssertEqual(Set(result.map(\.id)), Set([lapseTwo.id, suspended.id]))
        XCTAssertFalse(ids(for: .difficult, words: [lapseZero, lapseOne]).contains(lapseOne.id))
        XCTAssertTrue(ids(for: .difficult, words: [lapseTwo, lapseFive]).contains(lapseFive.id))
    }

    func testWordDetailLearningStateAndDueVisibility() {
        XCTAssertEqual(WordDetailLearningPresentation.make(progress: nil).stateName, "未学习")

        for (state, expectedName, expectsDue) in [
            (LearningState.new, "未学习", false),
            (.learning, "复习中", true),
            (.relearning, "复习中", true),
            (.review, "复习中", true),
            (.suspended, "已熟练", false)
        ] {
            let progress = LearningProgress(
                state: state,
                dueAt: Date(timeIntervalSinceReferenceDate: 10_600),
                intervalDays: 4,
                reviewCount: 3,
                lapseCount: 2,
                lastReviewedAt: Date(timeIntervalSinceReferenceDate: 9_000)
            )
            let presentation = WordDetailLearningPresentation.make(
                progress: progress,
                now: Date(timeIntervalSinceReferenceDate: 10_000)
            )
            XCTAssertEqual(presentation.stateName, expectedName)
            XCTAssertEqual(presentation.dueText != nil, expectsDue)
        }
    }

    func testLearningStatePresentationUsesThreeUserFacingStates() {
        XCTAssertEqual(LearningStatePresentation.name(for: nil), "未学习")
        XCTAssertEqual(LearningStatePresentation.name(for: .new), "未学习")
        XCTAssertEqual(LearningStatePresentation.name(for: .learning), "复习中")
        XCTAssertEqual(LearningStatePresentation.name(for: .relearning), "复习中")
        XCTAssertEqual(LearningStatePresentation.name(for: .review), "复习中")
        XCTAssertEqual(LearningStatePresentation.name(for: .suspended), "已熟练")
        XCTAssertEqual(WordbookStatusFilter.allCases.map(\.displayName), ["全部", "未学习", "复习中", "已熟练", "收藏", "易错词"])
    }

    func testWordDetailReusesRomajiPitchAndEtymologyPresentation() {
        let television = makeWord(
            "テレビ",
            reading: "テレビ",
            meaning: "电视",
            state: .new,
            sourceTerm: "television"
        )
        television.tags = ["音调:①"]
        let tv = WordDetailLexicalPresentation.make(for: television)
        XCTAssertEqual(tv.readingLine, "テレビ · terebi · [1]")
        XCTAssertEqual(tv.meaningLine, "电视 · television（英语）")

        let ramen = makeWord("ラーメン", meaning: "拉面", state: .new, sourceTerm: "拉麵", sourceLanguage: "zho")
        XCTAssertEqual(WordDetailLexicalPresentation.make(for: ramen).meaningLine, "拉面")

        let ballpen = makeWord("ボールペン", meaning: "圆珠笔", state: .new, sourceTerm: "ball pen", wasei: true)
        XCTAssertEqual(WordDetailLexicalPresentation.make(for: ballpen).meaningLine, "圆珠笔 · ball pen（和制英语）")
    }

    func testFavoritePersistenceDoesNotMutateLearningData() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let word = makeWord("確認", state: .review, lapseCount: 2)
        word.progress?.intervalDays = 12
        word.progress?.reviewCount = 4
        word.progress?.dueAt = Date(timeIntervalSinceReferenceDate: 12_000)
        context.insert(word)
        try context.save()

        try service.setFavorite(true, for: word, in: context, now: Date(timeIntervalSinceReferenceDate: 20_000))

        XCTAssertTrue(word.isFavorite)
        XCTAssertEqual(word.progress?.state, .review)
        XCTAssertEqual(word.progress?.intervalDays, 12)
        XCTAssertEqual(word.progress?.reviewCount, 4)
        XCTAssertEqual(word.progress?.lapseCount, 2)
        XCTAssertEqual(word.progress?.dueAt, Date(timeIntervalSinceReferenceDate: 12_000))
    }

    func testLargeFilteredWordbookReturnsOneExactPageWithoutRowFetches() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let book = WordBook(name: "JLPT N1")
        context.insert(book)
        for index in 0..<4_029 {
            let word = makeWord(
                String(format: "词%04d", index),
                meaning: index.isMultiple(of: 10) ? "目标" : "其他",
                state: .review
            )
            word.wordBook = book
            context.insert(word)
        }
        try context.save()

        var filters = allFilters()
        filters.searchText = "目标"
        let page = try service.fetchWordPage(
            in: context,
            scopedWordBookID: book.id,
            filters: filters,
            offset: 0,
            limit: WordbookViewModel.pageSize
        )

        XCTAssertEqual(page.rows.count, WordbookViewModel.pageSize)
        XCTAssertEqual(page.matchingCount, 403)
        XCTAssertTrue(page.isMatchingCountExact)
        XCTAssertTrue(page.hasNextPage)
    }

    private func allFilters() -> WordbookFilters {
        WordbookFilters(wordBookID: WordbookFilterValue.all.rawValue)
    }

    private func ids(for status: WordbookStatusFilter, words: [VocabularyWord]) -> Set<UUID> {
        var filters = allFilters()
        filters.status = status
        return Set(service.filter(words, using: filters, currentWordBookID: nil).map(\.id))
    }

    private func makeWord(
        _ expression: String,
        reading: String? = nil,
        meaning: String? = nil,
        state: LearningState?,
        favorite: Bool = false,
        lapseCount: Int = 0,
        sourceTerm: String? = nil,
        sourceLanguage: String? = "eng",
        wasei: Bool = false
    ) -> VocabularyWord {
        let word = VocabularyWord(
            japanese: expression,
            kana: reading ?? expression,
            chineseMeaning: meaning ?? expression,
            jlptLevel: "N5",
            isFavorite: favorite,
            loanwordSourceTerm: sourceTerm,
            loanwordSourceLanguageCode: sourceLanguage,
            loanwordIsWasei: wasei
        )
        if let state {
            word.progress = LearningProgress(state: state, lapseCount: lapseCount, word: word)
        }
        return word
    }
}
