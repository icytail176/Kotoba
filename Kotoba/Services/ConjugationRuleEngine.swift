//
//  ConjugationRuleEngine.swift
//  Kotoba
//
//  Created by Codex on 2026/6/17.
//

import Foundation

struct ConjugationRuleEngine {
    private let tokenizer = PartOfSpeechTokenizer()

    func generate(for word: VocabularyWord) -> GeneratedConjugation? {
        let request = ConjugationGenerationRequest(
            wordID: word.id,
            expression: word.japanese,
            reading: word.kana,
            meaningChinese: word.chineseMeaning,
            partOfSpeech: word.partOfSpeech
        )
        return generate(for: request)
    }

    func generate(for request: ConjugationGenerationRequest) -> GeneratedConjugation? {
        let tokens = Set(tokenizer.tokens(from: request.partOfSpeech))
        let expression = request.expression.trimmingCharacters(in: .whitespacesAndNewlines)
        let reading = request.reading.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !expression.isEmpty, !reading.isEmpty else {
            return nil
        }

        if tokens.contains("一段动词") || tokens.contains("一段動詞") {
            return ichidanVerb(request, expression: expression, reading: reading)
        }

        if tokens.contains("五段动词") || tokens.contains("五段動詞") {
            return godanVerb(request, expression: expression, reading: reading)
        }

        if tokens.contains("サ变动词") || tokens.contains("サ変動詞") || tokens.contains("する动词") {
            return suruVerb(request, expression: expression, reading: reading)
        }

        if tokens.contains("カ变动词") || tokens.contains("カ変動詞") || expression == "来る" || expression == "くる" {
            return kuruVerb(request, expression: expression)
        }

        if tokens.contains("い形容词") || tokens.contains("い形容詞") {
            return iAdjective(request, expression: expression, reading: reading)
        }

        if tokens.contains("な形容词") || tokens.contains("な形容詞") {
            return naAdjective(request, expression: expression, reading: reading)
        }

        if tokens.contains("名词") || tokens.contains("名詞") || tokens.contains("副词") || tokens.contains("副詞") {
            return noConjugation(request, expression: expression, reading: reading)
        }

        return nil
    }

    private func noConjugation(
        _ request: ConjugationGenerationRequest,
        expression: String,
        reading: String
    ) -> GeneratedConjugation {
        generated(
            request,
            conjugationClass: .none,
            forms: [form(.dictionary, expression, reading)]
        )
    }

    private func ichidanVerb(
        _ request: ConjugationGenerationRequest,
        expression: String,
        reading: String
    ) -> GeneratedConjugation? {
        guard expression.hasSuffix("る"), reading.hasSuffix("る") else {
            return nil
        }

        let expressionStem = String(expression.dropLast())
        let readingStem = String(reading.dropLast())
        return generated(
            request,
            conjugationClass: .ichidanVerb,
            forms: [
                form(.dictionary, expression, reading),
                form(.polite, expressionStem + "ます", readingStem + "ます"),
                form(.negative, expressionStem + "ない", readingStem + "ない"),
                form(.past, expressionStem + "た", readingStem + "た"),
                form(.teForm, expressionStem + "て", readingStem + "て")
            ]
        )
    }

    private func suruVerb(
        _ request: ConjugationGenerationRequest,
        expression: String,
        reading: String
    ) -> GeneratedConjugation {
        let expressionStem = expression.hasSuffix("する") ? String(expression.dropLast(2)) : expression
        let readingStem = reading.hasSuffix("する") ? String(reading.dropLast(2)) : reading
        return generated(
            request,
            conjugationClass: .suruVerb,
            forms: [
                form(.dictionary, expression, reading),
                form(.polite, expressionStem + "します", readingStem + "します"),
                form(.negative, expressionStem + "しない", readingStem + "しない"),
                form(.past, expressionStem + "した", readingStem + "した"),
                form(.teForm, expressionStem + "して", readingStem + "して")
            ]
        )
    }

    private func kuruVerb(
        _ request: ConjugationGenerationRequest,
        expression: String
    ) -> GeneratedConjugation {
        let usesKanjiSurface = expression == "来る"
        return generated(
            request,
            conjugationClass: .kuruVerb,
            forms: [
                form(.dictionary, expression, "くる"),
                form(.polite, usesKanjiSurface ? "来ます" : "きます", "きます"),
                form(.negative, usesKanjiSurface ? "来ない" : "こない", "こない"),
                form(.past, usesKanjiSurface ? "来た" : "きた", "きた"),
                form(.teForm, usesKanjiSurface ? "来て" : "きて", "きて")
            ]
        )
    }

    private func iAdjective(
        _ request: ConjugationGenerationRequest,
        expression: String,
        reading: String
    ) -> GeneratedConjugation? {
        guard expression.hasSuffix("い"), reading.hasSuffix("い") else {
            return nil
        }

        let expressionStem = String(expression.dropLast())
        let readingStem = String(reading.dropLast())
        return generated(
            request,
            conjugationClass: .iAdjective,
            forms: [
                form(.dictionary, expression, reading),
                form(.negative, expressionStem + "くない", readingStem + "くない"),
                form(.past, expressionStem + "かった", readingStem + "かった"),
                form(.teForm, expressionStem + "くて", readingStem + "くて")
            ]
        )
    }

    private func naAdjective(
        _ request: ConjugationGenerationRequest,
        expression: String,
        reading: String
    ) -> GeneratedConjugation {
        generated(
            request,
            conjugationClass: .naAdjective,
            forms: [
                form(.dictionary, expression, reading),
                form(.polite, expression + "です", reading + "です"),
                form(.negative, expression + "ではない", reading + "ではない"),
                form(.past, expression + "だった", reading + "だった"),
                form(.connective, expression + "で", reading + "で")
            ]
        )
    }

    private func godanVerb(
        _ request: ConjugationGenerationRequest,
        expression: String,
        reading: String
    ) -> GeneratedConjugation? {
        if expression == "行く" || expression == "いく" {
            return generated(
                request,
                conjugationClass: .godanVerb,
                forms: [
                    form(.dictionary, expression, reading),
                    form(.polite, "行きます", "いきます"),
                    form(.negative, "行かない", "いかない"),
                    form(.past, "行った", "いった"),
                    form(.teForm, "行って", "いって")
                ]
            )
        }

        guard let expressionEnding = expression.last,
              let readingEnding = reading.last,
              let expressionForms = godanEndings[expressionEnding],
              let readingForms = godanEndings[readingEnding] else {
            return nil
        }

        let expressionStem = String(expression.dropLast())
        let readingStem = String(reading.dropLast())
        return generated(
            request,
            conjugationClass: .godanVerb,
            forms: [
                form(.dictionary, expression, reading),
                form(.polite, expressionStem + expressionForms.masu, readingStem + readingForms.masu),
                form(.negative, expressionStem + expressionForms.negative, readingStem + readingForms.negative),
                form(.past, expressionStem + expressionForms.past, readingStem + readingForms.past),
                form(.teForm, expressionStem + expressionForms.te, readingStem + readingForms.te)
            ]
        )
    }

    private var godanEndings: [Character: (masu: String, negative: String, past: String, te: String)] {
        [
            "う": ("い", "わない", "った", "って"),
            "く": ("き", "かない", "いた", "いて"),
            "ぐ": ("ぎ", "がない", "いだ", "いで"),
            "す": ("し", "さない", "した", "して"),
            "つ": ("ち", "たない", "った", "って"),
            "ぬ": ("に", "なない", "んだ", "んで"),
            "ぶ": ("び", "ばない", "んだ", "んで"),
            "む": ("み", "まない", "んだ", "んで"),
            "る": ("り", "らない", "った", "って")
        ]
    }

    private func generated(
        _ request: ConjugationGenerationRequest,
        conjugationClass: ConjugationClass,
        forms: [ConjugationForm]
    ) -> GeneratedConjugation {
        GeneratedConjugation(
            wordID: request.wordID,
            expression: request.expression,
            reading: request.reading,
            conjugationClass: conjugationClass,
            forms: forms,
            source: .localRule,
            modelName: "local-rule"
        )
    }

    private func form(_ type: ConjugationFormType, _ surface: String, _ reading: String) -> ConjugationForm {
        ConjugationForm(type: type, surface: surface, reading: reading)
    }
}
