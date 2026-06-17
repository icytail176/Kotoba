//
//  SpellingAndConjugationTests.swift
//  KotobaTests
//
//  Created by Codex on 2026/6/17.
//

import XCTest

@MainActor
final class SpellingAndConjugationTests: XCTestCase {
    func testKanaAnswerNormalizationConvertsKatakanaToHiragana() {
        let normalizer = SpellingAnswerNormalizer()

        XCTAssertTrue(
            normalizer.isCorrect(
                answer: "　タベマス ",
                expected: "たべます",
                acceptsKanaOnly: true
            )
        )
    }

    func testSpellingSessionRetriesWrongAnswersOnce() {
        let question = SpellingQuestion(
            wordID: UUID(),
            direction: .readingToExpression,
            prompt: "たべる",
            expectedAnswer: "食べる",
            referenceText: "吃",
            wordExpression: "食べる",
            wordReading: "たべる",
            meaningChinese: "吃",
            exampleJapanese: "ご飯を食べる。"
        )
        let viewModel = SpellingSessionViewModel(questions: [question])

        viewModel.answer = "食べた"
        XCTAssertTrue(viewModel.submitAnswer())
        XCTAssertEqual(viewModel.feedback, .incorrect)
        viewModel.advance()

        XCTAssertTrue(viewModel.isRetryRound)
        XCTAssertNil(viewModel.summary)

        viewModel.answer = "食べる"
        XCTAssertTrue(viewModel.submitAnswer())
        viewModel.advance()

        XCTAssertEqual(viewModel.summary?.totalCount, 1)
        XCTAssertEqual(viewModel.summary?.firstAttemptCorrectCount, 0)
        XCTAssertEqual(viewModel.summary?.retryCorrectCount, 1)
        XCTAssertEqual(viewModel.summary?.remainingIncorrectCount, 0)
    }

    func testMarkedTextDoesNotSubmitSpellingAnswer() {
        let question = SpellingQuestion(
            wordID: UUID(),
            direction: .expressionToReading,
            prompt: "学生",
            expectedAnswer: "がくせい",
            referenceText: "学生",
            wordExpression: "学生",
            wordReading: "がくせい",
            meaningChinese: "学生",
            exampleJapanese: ""
        )
        let viewModel = SpellingSessionViewModel(questions: [question])
        viewModel.answer = "がくせい"

        XCTAssertFalse(viewModel.submitAnswer(isMarkedTextActive: true))
        XCTAssertFalse(viewModel.isAnswerLocked)
    }

    func testLocalConjugationGeneratesIchidanVerbForms() throws {
        let word = VocabularyWord(
            japanese: "食べる",
            kana: "たべる",
            chineseMeaning: "吃",
            partOfSpeech: "一段动词",
            jlptLevel: "N5"
        )
        let generated = try XCTUnwrap(ConjugationRuleEngine().generate(for: word))

        XCTAssertEqual(generated.conjugationClass, .ichidanVerb)
        XCTAssertTrue(generated.forms.contains(.init(type: .polite, surface: "食べます", reading: "たべます")))
        XCTAssertTrue(generated.forms.contains(.init(type: .past, surface: "食べた", reading: "たべた")))
    }

    func testInvalidConjugationOutputIsRejected() {
        let request = ConjugationGenerationRequest(
            wordID: UUID(),
            expression: "勉強する",
            reading: "べんきょうする",
            meaningChinese: "学习",
            partOfSpeech: "サ变动词"
        )
        let generated = GeneratedConjugation(
            wordID: request.wordID,
            expression: request.expression,
            reading: request.reading,
            conjugationClass: .suruVerb,
            forms: [
                .init(type: .dictionary, surface: "勉強する", reading: "べんきょうする"),
                .init(type: .polite, surface: "勉強するする", reading: "べんきょうするする")
            ],
            source: .lmStudio,
            modelName: "test"
        )

        XCTAssertEqual(
            ConjugationValidationService().validate(generated, for: request),
            .invalid
        )
    }

    func testLMStudioProviderRejectsNonLocalURL() async throws {
        let request = ConjugationGenerationRequest(
            wordID: UUID(),
            expression: "食べる",
            reading: "たべる",
            meaningChinese: "吃",
            partOfSpeech: "一段动词"
        )
        let provider = LMStudioConjugationProvider(
            baseURL: try XCTUnwrap(URL(string: "https://example.com/v1")),
            modelName: "test",
            timeout: 5
        )

        do {
            _ = try await provider.generateConjugations(requests: [request])
            XCTFail("Expected non-local URL to be rejected")
        } catch let error as ConjugationProviderError {
            XCTAssertEqual(error, .invalidLocalURL)
        }
    }
}
