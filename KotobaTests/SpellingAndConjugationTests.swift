//
//  SpellingAndConjugationTests.swift
//  KotobaTests
//

import XCTest
import SwiftUI
@testable import Kotoba

@MainActor
final class SpellingAndConjugationTests: XCTestCase {
    func testKanaAnswerNormalizationConvertsKatakanaAndIgnoresSpaces() {
        let normalizer = SpellingAnswerNormalizer()

        XCTAssertTrue(normalizer.isCorrect(answer: "　タベ マス ", expected: "たべます", acceptsKanaOnly: true))
        XCTAssertFalse(normalizer.isCorrect(answer: "食べます", expected: "たべます", acceptsKanaOnly: true))
    }

    func testExpressionRoundIncludesKanjiHiraganaAndKatakanaWithoutRevealingReading() throws {
        let words = [
            VocabularyWord(japanese: "食べる", kana: "たべる", chineseMeaning: "吃", jlptLevel: "N5", exampleJapanese: "朝ご飯を食べる。"),
            VocabularyWord(japanese: "ゆっくり", kana: "ゆっくり", chineseMeaning: "慢慢地", jlptLevel: "N4"),
            VocabularyWord(japanese: "コンピューター", kana: "コンピューター", chineseMeaning: "电脑", jlptLevel: "N5")
        ]
        let questions = SpellingQuestionGenerator().generateExpressionQuestions(words: words)

        XCTAssertEqual(Set(questions.map(\.wordID)), Set(words.map(\.id)))
        XCTAssertTrue(questions.allSatisfy { $0.direction == .meaningToExpression })
        XCTAssertEqual(try XCTUnwrap(questions.first { $0.wordExpression == "食べる" }).contextText, "朝ご飯を＿＿＿＿。")
        XCTAssertTrue(questions.allSatisfy { $0.prompt != $0.wordReading })
    }

    func testReadingRoundUsesActualKanjiDetection() {
        let values: [(String, String, Bool)] = [
            ("食べる", "たべる", true), ("申し込む", "もうしこむ", true), ("勉強", "べんきょう", true), ("一人", "ひとり", true),
            ("ゆっくり", "ゆっくり", false), ("きれい", "きれい", false), ("コンピューター", "コンピューター", false), ("テレビ", "テレビ", false)
        ]
        let words = values.map { VocabularyWord(japanese: $0.0, kana: $0.1, chineseMeaning: "测试", jlptLevel: "N5") }
        let generatedIDs = Set(SpellingQuestionGenerator().generateReadingQuestions(words: words).map(\.wordID))

        for (word, value) in zip(words, values) {
            XCTAssertEqual(containsKanji(value.0), value.2)
            XCTAssertEqual(generatedIDs.contains(word.id), value.2)
        }
        XCTAssertTrue(containsKanji("\u{20000}"))
        XCTAssertTrue(containsKanji("\u{2F800}"))
    }

    func testHintIsIrreversibleForAppearanceAndRequiresCleanRequeuePass() throws {
        let question = SpellingQuestion(
            wordID: UUID(),
            direction: .meaningToExpression,
            prompt: "吃",
            expectedAnswer: "食べる",
            referenceText: "根据意思写单词",
            wordExpression: "食べる",
            wordReading: "たべる",
            meaningChinese: "吃",
            exampleJapanese: ""
        )
        let viewModel = SpellingSessionViewModel(expressionQuestions: [question], readingQuestions: [])

        XCTAssertTrue(viewModel.revealHint())
        XCTAssertFalse(viewModel.revealHint())
        XCTAssertTrue(viewModel.isHintVisible)
        viewModel.answer = "食べる"
        XCTAssertEqual(viewModel.handleEnter(), .submitted)
        XCTAssertTrue(viewModel.currentCorrectAnswerWasRequeued)
        XCTAssertEqual(viewModel.handleEnter(), .advanced)
        XCTAssertFalse(viewModel.isHintVisible)
        XCTAssertEqual(viewModel.phase, .expression)

        viewModel.answer = "食べる"
        XCTAssertEqual(viewModel.handleEnter(), .submitted)
        XCTAssertFalse(viewModel.currentCorrectAnswerWasRequeued)
        XCTAssertEqual(viewModel.handleEnter(), .completed)
        let summary = try XCTUnwrap(viewModel.summary)
        XCTAssertEqual(summary.expression.totalCount, 1)
        XCTAssertEqual(summary.expression.firstAttemptCorrectCount, 0)
        XCTAssertEqual(summary.expression.retryCorrectCount, 1)
        XCTAssertEqual(summary.expression.usedHintCount, 1)
        XCTAssertEqual(summary.expression.firstAttemptCorrectCount + summary.expression.retryCorrectCount, summary.expression.totalCount)
        XCTAssertLessThanOrEqual(summary.expression.usedHintCount, summary.expression.retryCorrectCount)
    }

    func testWrongAnswerStaysThenRequeuesOnlyOnceAndTwoPhasesAreOrdered() throws {
        let expressionQuestion = SpellingQuestion(
            wordID: UUID(), direction: .meaningToExpression, prompt: "吃", expectedAnswer: "食べる",
            referenceText: "", wordExpression: "食べる", wordReading: "たべる", meaningChinese: "吃", exampleJapanese: ""
        )
        let readingQuestion = SpellingQuestion(
            wordID: expressionQuestion.wordID, direction: .expressionToReading, prompt: "食べる", expectedAnswer: "たべる",
            referenceText: "", wordExpression: "食べる", wordReading: "たべる", meaningChinese: "吃", exampleJapanese: ""
        )
        let viewModel = SpellingSessionViewModel(expressionQuestions: [expressionQuestion], readingQuestions: [readingQuestion])

        viewModel.answer = "食べます"
        XCTAssertEqual(viewModel.handleEnter(), .submitted)
        XCTAssertFalse(viewModel.isAnswerLocked)
        XCTAssertEqual(viewModel.currentIndex, 0)

        viewModel.answer = "食べません"
        XCTAssertEqual(viewModel.handleEnter(), .submitted)
        XCTAssertEqual(viewModel.currentIndex, 0)

        viewModel.answer = "食べる"
        XCTAssertEqual(viewModel.handleEnter(), .submitted)
        XCTAssertEqual(viewModel.handleEnter(), .advanced)
        XCTAssertEqual(viewModel.answer, "")

        viewModel.answer = "食べる"
        XCTAssertEqual(viewModel.handleEnter(), .submitted)
        XCTAssertEqual(viewModel.handleEnter(), .advanced)
        XCTAssertEqual(viewModel.phase, .reading)
        XCTAssertNil(viewModel.summary)

        viewModel.answer = "タベル"
        XCTAssertEqual(viewModel.handleEnter(), .submitted)
        XCTAssertEqual(viewModel.handleEnter(), .completed)
        let result = try XCTUnwrap(viewModel.summary?.resultsByWordID[expressionQuestion.wordID])
        XCTAssertEqual(result.expression.wrongCount, 2)
        XCTAssertEqual(result.expression.requeueCount, 1)
        XCTAssertEqual(result.reading.requeueCount, 0)
        XCTAssertEqual(viewModel.summary?.expression.retryCorrectCount, 1)
        XCTAssertEqual(viewModel.summary?.reading.firstAttemptCorrectCount, 1)
    }

    func testReadingRoundWrongThenCorrectRequeuesExactlyOnce() throws {
        let question = SpellingQuestion(
            wordID: UUID(),
            direction: .expressionToReading,
            prompt: "確認",
            expectedAnswer: "かくにん",
            referenceText: "根据单词写假名",
            wordExpression: "確認",
            wordReading: "かくにん",
            meaningChinese: "确认",
            exampleJapanese: ""
        )
        let viewModel = SpellingSessionViewModel(expressionQuestions: [], readingQuestions: [question])

        viewModel.answer = "かくじん"
        XCTAssertEqual(viewModel.handleEnter(), .submitted)
        XCTAssertFalse(viewModel.isAnswerLocked)
        XCTAssertEqual(viewModel.currentIndex, 0)

        viewModel.answer = "カクニン"
        XCTAssertEqual(viewModel.handleEnter(), .submitted)
        XCTAssertTrue(viewModel.currentCorrectAnswerWasRequeued)
        XCTAssertEqual(viewModel.handleEnter(), .advanced)
        XCTAssertEqual(viewModel.phase, .reading)
        XCTAssertEqual(viewModel.currentIndex, 1)

        viewModel.answer = "かくにん"
        XCTAssertEqual(viewModel.handleEnter(), .submitted)
        XCTAssertFalse(viewModel.currentCorrectAnswerWasRequeued)
        XCTAssertEqual(viewModel.handleEnter(), .completed)

        let summary = try XCTUnwrap(viewModel.summary)
        let result = try XCTUnwrap(summary.resultsByWordID[question.wordID])
        XCTAssertEqual(result.reading.wrongCount, 1)
        XCTAssertEqual(result.reading.requeueCount, 1)
        XCTAssertFalse(result.reading.passedFirstTry)
        XCTAssertEqual(summary.reading.totalCount, 1)
        XCTAssertEqual(summary.reading.firstAttemptCorrectCount, 0)
        XCTAssertEqual(summary.reading.retryCorrectCount, 1)
        XCTAssertEqual(Set(result.errorTypes), Set([.reading, .readingDirection]))
    }

    func testHintShortcutIsExactFirstRoundCommandShiftHAndIMEAware() {
        XCTAssertTrue(SpellingHintShortcutPolicy.shouldHandle(
            phase: .expression, isRepeat: false, modifiers: [.command, .shift], keyCode: 4, characters: "h", hasMarkedText: false
        ))
        XCTAssertFalse(SpellingHintShortcutPolicy.shouldHandle(
            phase: .expression, isRepeat: false, modifiers: [], keyCode: 4, characters: "h", hasMarkedText: false
        ))
        XCTAssertFalse(SpellingHintShortcutPolicy.shouldHandle(
            phase: .expression, isRepeat: false, modifiers: [.command], keyCode: 4, characters: "h", hasMarkedText: false
        ))
        XCTAssertFalse(SpellingHintShortcutPolicy.shouldHandle(
            phase: .expression, isRepeat: false, modifiers: [.command, .shift], keyCode: 4, characters: "h", hasMarkedText: true
        ))
        XCTAssertFalse(SpellingHintShortcutPolicy.shouldHandle(
            phase: .reading, isRepeat: false, modifiers: [.command, .shift], keyCode: 4, characters: "h", hasMarkedText: false
        ))
    }

    func testLoanwordPresentationHidesMissingAndDistinguishesWaseiAndPartial() throws {
        let word = VocabularyWord(japanese: "コンピューター", kana: "コンピューター", chineseMeaning: "电脑", jlptLevel: "N5")
        XCTAssertNil(LoanwordEtymologyPresentation.make(for: word))

        word.loanwordSourceTerm = "computer"
        word.loanwordSourceLanguageCode = "eng"
        let standard = try XCTUnwrap(LoanwordEtymologyPresentation.make(for: word))
        XCTAssertEqual(standard.title, "外来语词源")
        XCTAssertEqual(standard.sourceTerm, "computer")
        XCTAssertEqual(standard.sourceLanguageName, "英语")
        XCTAssertEqual(standard.value, "computer（英语）")

        word.loanwordSourceTerm = "salary + man"
        word.loanwordIsWasei = true
        XCTAssertEqual(LoanwordEtymologyPresentation.make(for: word)?.value, "salary + man（和制英语）")

        word.loanwordSourceTerm = "form"
        word.loanwordIsWasei = false
        word.loanwordIsPartial = true
        let partial = try XCTUnwrap(LoanwordEtymologyPresentation.make(for: word))
        XCTAssertEqual(partial.title, "部分词源")
        XCTAssertEqual(partial.value, "form（英语）")
        XCTAssertEqual(partial.inlineValue, "form（英语） · 部分词源")
    }

    func testLocalVerbRulesGenerateCoreForms() throws {
        let cases: [(String, String, String, [ConjugationFormType: String])] = [
            ("食べる", "たべる", "一段动词", [.polite: "食べます", .negative: "食べない", .past: "食べた", .teForm: "食べて"]),
            ("書く", "かく", "五段动词", [.polite: "書きます", .negative: "書かない", .past: "書いた", .teForm: "書いて"]),
            ("確認する", "かくにんする", "サ变动词", [.polite: "確認します", .negative: "確認しない", .past: "確認した", .teForm: "確認して"]),
            ("来る", "くる", "カ变动词", [.polite: "来ます", .negative: "来ない", .past: "来た", .teForm: "来て"])
        ]

        for (expression, reading, partOfSpeech, expected) in cases {
            let generated = try XCTUnwrap(makeConjugation(expression, reading, partOfSpeech))
            for (type, surface) in expected {
                XCTAssertEqual(generated.forms.first { $0.type == type }?.surface, surface)
            }
        }
    }

    func testLocalAdjectiveRulesGenerateCoreForms() throws {
        let iAdjective = try XCTUnwrap(makeConjugation("高い", "たかい", "い形容词"))
        XCTAssertEqual(iAdjective.forms.first { $0.type == .negative }?.surface, "高くない")
        XCTAssertEqual(iAdjective.forms.first { $0.type == .past }?.surface, "高かった")
        XCTAssertEqual(iAdjective.forms.first { $0.type == .teForm }?.surface, "高くて")
        XCTAssertEqual(iAdjective.forms.first { $0.type == .adverbial }?.surface, "高く")

        let naAdjective = try XCTUnwrap(makeConjugation("静か", "しずか", "な形容词"))
        XCTAssertEqual(naAdjective.forms.first { $0.type == .polite }?.surface, "静かです")
        XCTAssertEqual(naAdjective.forms.first { $0.type == .negative }?.surface, "静かではない")
        XCTAssertEqual(naAdjective.forms.first { $0.type == .past }?.surface, "静かだった")
        XCTAssertEqual(naAdjective.forms.first { $0.type == .connective }?.surface, "静かで")
        XCTAssertEqual(naAdjective.forms.first { $0.type == .adverbial }?.surface, "静かに")
    }

    func testAmbiguousGenericPartOfSpeechDoesNotGuess() {
        XCTAssertNil(makeConjugation("帰る", "かえる", "动词"))
        XCTAssertNil(makeConjugation("きれい", "きれい", "形容词"))
    }

    func testConjugationIsGeneratedLiveFromCurrentWordFields() throws {
        let word = VocabularyWord(
            japanese: "食べる",
            kana: "たべる",
            chineseMeaning: "吃",
            partOfSpeech: "一段动词",
            jlptLevel: "N5"
        )
        let engine = ConjugationEngine()
        XCTAssertEqual(try XCTUnwrap(engine.generate(for: word)).forms.first { $0.type == .polite }?.surface, "食べます")

        word.japanese = "見る"
        word.kana = "みる"
        XCTAssertEqual(try XCTUnwrap(engine.generate(for: word)).forms.first { $0.type == .polite }?.surface, "見ます")
    }

    func testStudyCardOnlyAddsSecondPageWhenConjugationFormsExist() throws {
        let verb = try XCTUnwrap(makeConjugation("食べる", "たべる", "一段动词"))
        let visibleForms = StudyCardContent.conjugationForms(from: verb)

        XCTAssertEqual(StudyCardContent.pageCount(for: nil), 1)
        XCTAssertEqual(StudyCardContent.pageCount(for: verb), 2)
        XCTAssertFalse(visibleForms.isEmpty)
        XCTAssertFalse(visibleForms.contains { $0.type == .dictionary })
    }

    func testConjugationFormsRenderInTwoColumnsAtStudyWidths() throws {
        let conjugation = try XCTUnwrap(makeConjugation("食べる", "たべる", "一段动词"))
        let forms = StudyCardContent.conjugationForms(from: conjugation)

        for width in [480.0, 720.0] {
            let renderer = ImageRenderer(
                content: ConjugationFormsListView(forms: forms, columnCount: 2)
                    .frame(width: width)
            )
            renderer.proposedSize = ProposedViewSize(width: width, height: 520)

            let image = try XCTUnwrap(renderer.nsImage)
            XCTAssertEqual(image.size.width, width, accuracy: 0.5)
            XCTAssertGreaterThan(image.size.height, 0)
        }
    }

    func testStudyCardKeyboardMappingUsesDeleteForEasyAndArrowsForPaging() {
        XCTAssertEqual(StudyCardKeyboardCommand.command(for: " "), .showAnswer)
        XCTAssertEqual(StudyCardKeyboardCommand.command(for: "1"), .rate(.again))
        XCTAssertEqual(StudyCardKeyboardCommand.command(for: "2"), .rate(.hard))
        XCTAssertEqual(StudyCardKeyboardCommand.command(for: "3"), .rate(.good))
        XCTAssertEqual(StudyCardKeyboardCommand.command(for: "\u{7F}"), .rate(.easy))
        XCTAssertEqual(StudyCardKeyboardCommand.command(for: "\u{F728}"), .rate(.easy))
        XCTAssertEqual(StudyCardKeyboardCommand.command(for: "\u{F702}"), .previousPage)
        XCTAssertEqual(StudyCardKeyboardCommand.command(for: "\u{F703}"), .nextPage)
        XCTAssertNil(StudyCardKeyboardCommand.command(for: "4"))
        XCTAssertEqual(StudyCardKeyboardCommand.command(forKeyCode: 18, characters: nil), .rate(.again))
        XCTAssertEqual(StudyCardKeyboardCommand.command(forKeyCode: 19, characters: nil), .rate(.hard))
        XCTAssertEqual(StudyCardKeyboardCommand.command(forKeyCode: 20, characters: nil), .rate(.good))
        XCTAssertEqual(StudyCardKeyboardCommand.command(forKeyCode: 49, characters: nil), .showAnswer)
        XCTAssertEqual(StudyCardKeyboardCommand.command(forKeyCode: 51, characters: nil), .rate(.easy))
        XCTAssertEqual(StudyCardKeyboardCommand.command(forKeyCode: 117, characters: nil), .rate(.easy))
        XCTAssertEqual(StudyCardKeyboardCommand.command(forKeyCode: 123, characters: nil), .previousPage)
        XCTAssertEqual(StudyCardKeyboardCommand.command(forKeyCode: 124, characters: nil), .nextPage)
    }

    func testStudyKeyboardEventPolicyIgnoresTextEditingModifiersAndRepeats() {
        XCTAssertTrue(StudyKeyboardEventPolicy.shouldHandle(
            isRepeat: false,
            modifiers: [],
            firstResponder: nil
        ))
        XCTAssertFalse(StudyKeyboardEventPolicy.shouldHandle(
            isRepeat: true,
            modifiers: [],
            firstResponder: nil
        ))
        XCTAssertFalse(StudyKeyboardEventPolicy.shouldHandle(
            isRepeat: false,
            modifiers: .command,
            firstResponder: nil
        ))
        XCTAssertFalse(StudyKeyboardEventPolicy.shouldHandle(
            isRepeat: false,
            modifiers: [],
            firstResponder: NSTextField()
        ))
        XCTAssertFalse(StudyKeyboardEventPolicy.shouldHandle(
            isRepeat: false,
            modifiers: [],
            firstResponder: NSTextView()
        ))
    }

    func testStudyCardRendersAtNarrowStandardAndWideWindowWidths() throws {
        let word = VocabularyWord(
            japanese: "テレビ",
            kana: "テレビ",
            chineseMeaning: "电视以及电视广播节目",
            partOfSpeech: "名词",
            jlptLevel: "N5",
            exampleJapanese: "私はテレビをあまり見ません。",
            exampleChinese: "我不太看电视。",
            tags: ["音调:①"],
            loanwordSourceTerm: "television broadcasting and receiving equipment",
            loanwordSourceLanguageCode: "eng",
            loanwordIsPartial: true
        )
        let item = StudySession.Item(id: word.id, word: word, kind: .newWord, dueAt: Date())

        for size in [
            CGSize(width: 720, height: 560),
            CGSize(width: 900, height: 700),
            CGSize(width: 1_200, height: 800),
            CGSize(width: 1_440, height: 900)
        ] {
            let renderer = ImageRenderer(
                content: StudyCardView(
                    item: item,
                    progressText: "1 / 10",
                    isAnswerVisible: true,
                    isSubmittingRating: false,
                    conjugation: nil,
                    onShowAnswer: {},
                    onToggleFavorite: {},
                    onRate: { _ in }
                )
                .frame(width: size.width, height: size.height)
            )
            renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)

            let image = try XCTUnwrap(renderer.nsImage)
            XCTAssertEqual(image.size.width, size.width, accuracy: 0.5)
            XCTAssertEqual(image.size.height, size.height, accuracy: 0.5)
        }
    }

    private func makeConjugation(_ expression: String, _ reading: String, _ partOfSpeech: String) -> GeneratedConjugation? {
        ConjugationEngine().generate(
            for: ConjugationGenerationRequest(
                wordID: UUID(),
                expression: expression,
                reading: reading,
                meaningChinese: "",
                partOfSpeech: partOfSpeech
            )
        )
    }
}
