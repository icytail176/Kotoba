//
//  SpellingQuestionService.swift
//  Kotoba
//
//  Created by Codex on 2026/6/17.
//

import Foundation

enum SpellingQuestionDirection: String, Codable, CaseIterable, Identifiable {
    case meaningToExpression
    case readingToExpression
    case expressionToReading

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meaningToExpression:
            return "看中文写日语"
        case .readingToExpression:
            return "看假名写单词"
        case .expressionToReading:
            return "看单词写假名"
        }
    }
}

struct SpellingQuestion: Identifiable, Equatable {
    let id: UUID
    let wordID: UUID
    let direction: SpellingQuestionDirection
    let formType: ConjugationFormType?
    let prompt: String
    let expectedAnswer: String
    let referenceText: String
    let wordExpression: String
    let wordReading: String
    let meaningChinese: String
    let exampleJapanese: String

    init(
        id: UUID = UUID(),
        wordID: UUID,
        direction: SpellingQuestionDirection,
        formType: ConjugationFormType? = nil,
        prompt: String,
        expectedAnswer: String,
        referenceText: String,
        wordExpression: String,
        wordReading: String,
        meaningChinese: String,
        exampleJapanese: String
    ) {
        self.id = id
        self.wordID = wordID
        self.direction = direction
        self.formType = formType
        self.prompt = prompt
        self.expectedAnswer = expectedAnswer
        self.referenceText = referenceText
        self.wordExpression = wordExpression
        self.wordReading = wordReading
        self.meaningChinese = meaningChinese
        self.exampleJapanese = exampleJapanese
    }
}

struct SpellingAnswerNormalizer {
    func isCorrect(answer: String, expected: String, acceptsKanaOnly: Bool) -> Bool {
        if acceptsKanaOnly {
            return normalizedKana(answer) == normalizedKana(expected)
        }

        return normalizedText(answer) == normalizedText(expected)
    }

    func normalizedText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{3000}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCompatibilityMapping
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
}

struct SpellingQuestionGenerator {
    func generate(
        words: [VocabularyWord],
        conjugationRecords: [ConjugationRecord] = []
    ) -> [SpellingQuestion] {
        let recordsByWordID = Dictionary(grouping: conjugationRecords, by: \.wordID)
        var seenWordIDs = Set<UUID>()
        var seenQuestionKeys = Set<String>()
        var questions: [SpellingQuestion] = []

        for word in words where seenWordIDs.insert(word.id).inserted {
            appendQuestion(
                word: word,
                direction: .meaningToExpression,
                prompt: word.chineseMeaning,
                expectedAnswer: word.japanese,
                referenceText: word.kana,
                to: &questions,
                seenQuestionKeys: &seenQuestionKeys
            )

            if word.japanese != word.kana {
                appendQuestion(
                    word: word,
                    direction: .readingToExpression,
                    prompt: word.kana,
                    expectedAnswer: word.japanese,
                    referenceText: word.chineseMeaning,
                    to: &questions,
                    seenQuestionKeys: &seenQuestionKeys
                )

                appendQuestion(
                    word: word,
                    direction: .expressionToReading,
                    prompt: word.japanese,
                    expectedAnswer: word.kana,
                    referenceText: word.chineseMeaning,
                    to: &questions,
                    seenQuestionKeys: &seenQuestionKeys
                )
            }

            if let form = validConjugationForm(from: recordsByWordID[word.id]) {
                appendQuestion(
                    word: word,
                    direction: .readingToExpression,
                    formType: form.type,
                    prompt: form.reading,
                    expectedAnswer: form.surface,
                    referenceText: form.type.title,
                    to: &questions,
                    seenQuestionKeys: &seenQuestionKeys
                )

                if form.surface != form.reading {
                    appendQuestion(
                        word: word,
                        direction: .expressionToReading,
                        formType: form.type,
                        prompt: form.surface,
                        expectedAnswer: form.reading,
                        referenceText: form.type.title,
                        to: &questions,
                        seenQuestionKeys: &seenQuestionKeys
                    )
                }
            }
        }

        return separatedByWord(questions.shuffled())
    }

    private func validConjugationForm(from records: [ConjugationRecord]?) -> ConjugationForm? {
        records?
            .filter { $0.validationStatus == .valid && !$0.markedIncorrect }
            .flatMap(\.forms)
            .filter { $0.type != .dictionary }
            .shuffled()
            .first
    }

    private func separatedByWord(_ questions: [SpellingQuestion]) -> [SpellingQuestion] {
        var remaining = questions
        var result: [SpellingQuestion] = []
        var lastWordID: UUID?

        while !remaining.isEmpty {
            let candidateIndex = remaining.firstIndex { $0.wordID != lastWordID } ?? remaining.startIndex
            let next = remaining.remove(at: candidateIndex)
            result.append(next)
            lastWordID = next.wordID
        }

        return result
    }

    private func appendQuestion(
        word: VocabularyWord,
        direction: SpellingQuestionDirection,
        formType: ConjugationFormType? = nil,
        prompt: String,
        expectedAnswer: String,
        referenceText: String,
        to questions: inout [SpellingQuestion],
        seenQuestionKeys: inout Set<String>
    ) {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAnswer = expectedAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty, !trimmedAnswer.isEmpty else {
            return
        }

        let key = [
            word.id.uuidString,
            direction.rawValue,
            formType?.rawValue ?? "",
            trimmedPrompt,
            trimmedAnswer
        ].joined(separator: "\u{1F}")

        guard seenQuestionKeys.insert(key).inserted else {
            return
        }

        questions.append(
            SpellingQuestion(
                wordID: word.id,
                direction: direction,
                formType: formType,
                prompt: trimmedPrompt,
                expectedAnswer: trimmedAnswer,
                referenceText: referenceText,
                wordExpression: word.japanese,
                wordReading: word.kana,
                meaningChinese: word.chineseMeaning,
                exampleJapanese: word.exampleJapanese
            )
        )
    }
}
