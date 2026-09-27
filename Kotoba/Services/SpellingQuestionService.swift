//
//  SpellingQuestionService.swift
//  Kotoba
//
//  Created by Codex on 2026/6/17.
//

import Foundation

enum SpellingQuestionDirection: String, Codable, CaseIterable, Identifiable {
    case meaningToExpression
    case expressionToReading

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meaningToExpression:
            return "单词拼写"
        case .expressionToReading:
            return "看单词写假名"
        }
    }
}

struct SpellingQuestion: Identifiable, Equatable {
    let id: UUID
    let wordID: UUID
    let direction: SpellingQuestionDirection
    let prompt: String
    let expectedAnswer: String
    let referenceText: String
    let wordExpression: String
    let wordReading: String
    let meaningChinese: String
    let exampleJapanese: String
    let exampleChinese: String
    let contextText: String
    let hasExampleContext: Bool

    init(
        id: UUID = UUID(),
        wordID: UUID,
        direction: SpellingQuestionDirection,
        prompt: String,
        expectedAnswer: String,
        referenceText: String,
        wordExpression: String,
        wordReading: String,
        meaningChinese: String,
        exampleJapanese: String,
        exampleChinese: String = "",
        contextText: String? = nil,
        hasExampleContext: Bool? = nil
    ) {
        self.id = id
        self.wordID = wordID
        self.direction = direction
        self.prompt = prompt
        self.expectedAnswer = expectedAnswer
        self.referenceText = referenceText
        self.wordExpression = wordExpression
        self.wordReading = wordReading
        self.meaningChinese = meaningChinese
        self.exampleJapanese = exampleJapanese
        self.exampleChinese = exampleChinese
        self.contextText = contextText ?? exampleJapanese
        self.hasExampleContext = hasExampleContext ?? !exampleJapanese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum AnswerCheckKind: Equatable, Sendable {
    case expression
    case reading
}

struct AnswerCheckResult: Equatable, Sendable {
    let isCorrect: Bool
    let normalizedAnswer: String
    let normalizedExpected: String
}

struct AnswerChecker {
    func check(answer: String, expected: String, kind: AnswerCheckKind) -> AnswerCheckResult {
        let normalizedAnswer: String
        let normalizedExpected: String

        switch kind {
        case .expression:
            normalizedAnswer = normalizedText(answer)
            normalizedExpected = normalizedText(expected)
        case .reading:
            normalizedAnswer = normalizedKana(answer)
            normalizedExpected = normalizedKana(expected)
        }

        let isCorrect: Bool
        switch kind {
        case .expression:
            isCorrect = normalizedAnswer == normalizedExpected
        case .reading:
            isCorrect = isKanaReading(normalizedAnswer) && normalizedAnswer == normalizedExpected
        }

        return AnswerCheckResult(
            isCorrect: isCorrect,
            normalizedAnswer: normalizedAnswer,
            normalizedExpected: normalizedExpected
        )
    }

    func normalizedText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCompatibilityMapping
            .filter { character in
                character != " " && character != "\u{3000}"
            }
            .map(String.init)
            .joined()
    }

    func normalizedKana(_ value: String) -> String {
        String(
            normalizedText(value).unicodeScalars.map { scalar in
                guard (0x30A1...0x30F6).contains(Int(scalar.value)),
                      let hiragana = UnicodeScalar(scalar.value - 0x60) else {
                    return Character(scalar)
                }

                return Character(hiragana)
            }
        )
    }

    private func isKanaReading(_ value: String) -> Bool {
        guard !value.isEmpty else {
            return false
        }

        return value.unicodeScalars.allSatisfy { scalar in
            (0x3041...0x3096).contains(Int(scalar.value)) || scalar.value == 0x30FC
        }
    }
}

struct SpellingAnswerNormalizer {
    private let checker = AnswerChecker()

    func isCorrect(answer: String, expected: String, acceptsKanaOnly: Bool) -> Bool {
        if acceptsKanaOnly {
            return checker.check(answer: answer, expected: expected, kind: .reading).isCorrect
        }

        return checker.check(answer: answer, expected: expected, kind: .expression).isCorrect
    }

    func normalizedText(_ value: String) -> String {
        checker.normalizedText(value)
    }

    func normalizedKana(_ value: String) -> String {
        checker.normalizedKana(value)
    }
}

struct SpellingQuestionGenerator {
    func generateExpressionQuestions(words: [VocabularyWord]) -> [SpellingQuestion] {
        uniqueWords(words).compactMap { word in
            makeQuestion(
                word: word,
                direction: .meaningToExpression,
                prompt: word.chineseMeaning,
                expectedAnswer: word.japanese,
                referenceText: "根据释义和语境写出词典形"
            )
        }.shuffled()
    }

    func generateReadingQuestions(words: [VocabularyWord]) -> [SpellingQuestion] {
        uniqueWords(words).compactMap { word in
            guard containsKanji(word.japanese) else { return nil }
            return makeQuestion(
                word: word,
                direction: .expressionToReading,
                prompt: word.japanese,
                expectedAnswer: word.kana,
                referenceText: "看汉字词写假名"
            )
        }.shuffled()
    }

    private func uniqueWords(_ words: [VocabularyWord]) -> [VocabularyWord] {
        var seen = Set<UUID>()
        return words.filter { seen.insert($0.id).inserted }
    }

    private func makeQuestion(
        word: VocabularyWord,
        direction: SpellingQuestionDirection,
        prompt: String,
        expectedAnswer: String,
        referenceText: String
    ) -> SpellingQuestion? {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAnswer = expectedAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExpression = word.japanese.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReading = word.kana.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty,
              !trimmedAnswer.isEmpty,
              !trimmedExpression.isEmpty,
              !trimmedReading.isEmpty else {
            return nil
        }

        let target = direction == .meaningToExpression ? trimmedAnswer : trimmedExpression
        let context = exampleContext(for: word.exampleJapanese, target: target)
        return SpellingQuestion(
            wordID: word.id,
            direction: direction,
            prompt: trimmedPrompt,
            expectedAnswer: trimmedAnswer,
            referenceText: referenceText,
            wordExpression: word.japanese,
            wordReading: word.kana,
            meaningChinese: word.chineseMeaning,
            exampleJapanese: word.exampleJapanese,
            exampleChinese: word.exampleChinese,
            contextText: context.text,
            hasExampleContext: context.hasExample
        )
    }

    private func exampleContext(for example: String, target: String) -> (text: String, hasExample: Bool) {
        let trimmedExample = example.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedExample.isEmpty else {
            return ("", false)
        }

        let trimmedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTarget.isEmpty, trimmedExample.contains(trimmedTarget) else {
            return (trimmedExample, true)
        }

        return (trimmedExample.replacingOccurrences(of: trimmedTarget, with: "＿＿＿＿"), true)
    }
}

/// True when the string contains a Unicode CJK unified or compatibility
/// ideograph. The supplementary planes are included so this is not limited to
/// the common BMP `[一-龯]` approximation.
func containsKanji(_ value: String) -> Bool {
    value.unicodeScalars.contains { scalar in
        switch scalar.value {
        case 0x3400...0x4DBF,   // CJK Unified Ideographs Extension A
             0x4E00...0x9FFF,   // CJK Unified Ideographs
             0xF900...0xFAFF,   // CJK Compatibility Ideographs
             0x20000...0x2A6DF, // Extensions B
             0x2A700...0x2B73F, // Extension C
             0x2B740...0x2B81F, // Extension D
             0x2B820...0x2CEAF, // Extension E
             0x2CEB0...0x2EBEF, // Extension F
             0x2EBF0...0x2EE5F, // Extension I
             0x2F800...0x2FA1F, // Compatibility supplement
             0x30000...0x3134F, // Extension G
             0x31350...0x323AF: // Extension H
            return true
        default:
            return false
        }
    }
}
