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

        if let exception = builtInException(
            request,
            expression: expression,
            reading: reading,
            tokens: tokens
        ) {
            return exception
        }

        if containsAny(["一段动词", "一段動詞"], in: tokens) {
            return ichidanVerb(request, expression: expression, reading: reading)
        }

        if containsAny(["五段动词", "五段動詞"], in: tokens) {
            return godanVerb(request, expression: expression, reading: reading)
        }

        if containsAny(["サ变动词", "サ変動詞", "する动词", "する動詞"], in: tokens) {
            return suruVerb(request, expression: expression, reading: reading)
        }

        if containsAny(["い形容词", "い形容詞"], in: tokens) {
            return iAdjective(request, expression: expression, reading: reading)
        }

        if containsAny(["な形容词", "な形容詞"], in: tokens) {
            return naAdjective(request, expression: expression, reading: reading)
        }

        if containsAny(["名词", "名詞", "副词", "副詞"], in: tokens) {
            return noConjugation(request, expression: expression, reading: reading)
        }

        return nil
    }

    func generate(
        for request: ConjugationGenerationRequest,
        forcedClass: ConjugationClass
    ) -> GeneratedConjugation? {
        let expression = request.expression.trimmingCharacters(in: .whitespacesAndNewlines)
        let reading = request.reading.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !expression.isEmpty, !reading.isEmpty else {
            return nil
        }

        if let exception = builtInException(
            request,
            expression: expression,
            reading: reading,
            tokens: []
        ) {
            return exception
        }

        switch forcedClass {
        case .none:
            return noConjugation(request, expression: expression, reading: reading)
        case .ichidanVerb:
            return ichidanVerb(request, expression: expression, reading: reading)
        case .godanVerb:
            return godanVerb(request, expression: expression, reading: reading)
        case .suruVerb:
            return suruVerb(request, expression: expression, reading: reading)
        case .kuruVerb:
            return kuruVerb(request, expression: expression, reading: reading)
        case .iAdjective:
            return iAdjective(request, expression: expression, reading: reading)
        case .naAdjective:
            return naAdjective(request, expression: expression, reading: reading)
        case .unknown:
            return nil
        }
    }

    private func builtInException(
        _ request: ConjugationGenerationRequest,
        expression: String,
        reading: String,
        tokens: Set<String>
    ) -> GeneratedConjugation? {
        if expression == "いい", reading == "いい" {
            return goodIAdjective(request, expression: expression, reading: reading)
        }

        if expression == "来る" || expression == "くる" || containsAny(["カ变动词", "カ変動詞"], in: tokens) {
            return kuruVerb(request, expression: expression, reading: reading)
        }

        if expression == "行く" || expression == "いく" {
            return ikuVerb(request, expression: expression, reading: reading)
        }

        if expression == "ある", reading == "ある" {
            return aruVerb(request, expression: expression, reading: reading)
        }

        if expression == "する" || reading == "する" {
            return suruVerb(request, expression: expression, reading: reading)
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
        guard expression.hasSuffix("る"),
              reading.hasSuffix("る"),
              !knownGodanRuExpressions.contains(expression) else {
            return nil
        }

        let expressionStem = String(expression.dropLast())
        let readingStem = String(reading.dropLast())
        return generated(
            request,
            conjugationClass: .ichidanVerb,
            forms: verbForms(
                dictionarySurface: expression,
                dictionaryReading: reading,
                polite: (expressionStem + "ます", readingStem + "ます"),
                negative: (expressionStem + "ない", readingStem + "ない"),
                past: (expressionStem + "た", readingStem + "た"),
                te: (expressionStem + "て", readingStem + "て"),
                conditional: (expressionStem + "れば", readingStem + "れば"),
                potential: (expressionStem + "られる", readingStem + "られる"),
                volitional: (expressionStem + "よう", readingStem + "よう"),
                imperative: (expressionStem + "ろ", readingStem + "ろ"),
                passive: (expressionStem + "られる", readingStem + "られる"),
                causative: (expressionStem + "させる", readingStem + "させる"),
                causativePassive: (expressionStem + "させられる", readingStem + "させられる")
            )
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
            forms: verbForms(
                dictionarySurface: expression,
                dictionaryReading: reading,
                polite: (expressionStem + "します", readingStem + "します"),
                negative: (expressionStem + "しない", readingStem + "しない"),
                past: (expressionStem + "した", readingStem + "した"),
                te: (expressionStem + "して", readingStem + "して"),
                conditional: (expressionStem + "すれば", readingStem + "すれば"),
                potential: (expressionStem + "できる", readingStem + "できる"),
                volitional: (expressionStem + "しよう", readingStem + "しよう"),
                imperative: (expressionStem + "しろ", readingStem + "しろ"),
                passive: (expressionStem + "される", readingStem + "される"),
                causative: (expressionStem + "させる", readingStem + "させる"),
                causativePassive: (expressionStem + "させられる", readingStem + "させられる")
            )
        )
    }

    private func kuruVerb(
        _ request: ConjugationGenerationRequest,
        expression: String,
        reading: String
    ) -> GeneratedConjugation? {
        let expressionPrefix: String
        let usesKanjiSurface: Bool
        if expression.hasSuffix("来る") {
            expressionPrefix = String(expression.dropLast(2))
            usesKanjiSurface = true
        } else if expression.hasSuffix("くる") {
            expressionPrefix = String(expression.dropLast(2))
            usesKanjiSurface = false
        } else {
            return nil
        }

        guard reading.hasSuffix("くる") else {
            return nil
        }

        let readingPrefix = String(reading.dropLast(2))
        return generated(
            request,
            conjugationClass: .kuruVerb,
            forms: verbForms(
                dictionarySurface: expression,
                dictionaryReading: reading,
                polite: (expressionPrefix + (usesKanjiSurface ? "来ます" : "きます"), readingPrefix + "きます"),
                negative: (expressionPrefix + (usesKanjiSurface ? "来ない" : "こない"), readingPrefix + "こない"),
                past: (expressionPrefix + (usesKanjiSurface ? "来た" : "きた"), readingPrefix + "きた"),
                te: (expressionPrefix + (usesKanjiSurface ? "来て" : "きて"), readingPrefix + "きて"),
                conditional: (expressionPrefix + (usesKanjiSurface ? "来れば" : "くれば"), readingPrefix + "くれば"),
                potential: (expressionPrefix + (usesKanjiSurface ? "来られる" : "こられる"), readingPrefix + "こられる"),
                volitional: (expressionPrefix + (usesKanjiSurface ? "来よう" : "こよう"), readingPrefix + "こよう"),
                imperative: (expressionPrefix + (usesKanjiSurface ? "来い" : "こい"), readingPrefix + "こい"),
                passive: (expressionPrefix + (usesKanjiSurface ? "来られる" : "こられる"), readingPrefix + "こられる"),
                causative: (expressionPrefix + (usesKanjiSurface ? "来させる" : "こさせる"), readingPrefix + "こさせる"),
                causativePassive: (expressionPrefix + (usesKanjiSurface ? "来させられる" : "こさせられる"), readingPrefix + "こさせられる")
            )
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
                form(.polite, expression + "です", reading + "です"),
                form(.negative, expressionStem + "くない", readingStem + "くない"),
                form(.past, expressionStem + "かった", readingStem + "かった"),
                form(.teForm, expressionStem + "くて", readingStem + "くて"),
                form(.conditional, expressionStem + "ければ", readingStem + "ければ"),
                form(.adverbial, expressionStem + "く", readingStem + "く")
            ]
        )
    }

    private func goodIAdjective(
        _ request: ConjugationGenerationRequest,
        expression: String,
        reading: String
    ) -> GeneratedConjugation {
        generated(
            request,
            conjugationClass: .iAdjective,
            forms: [
                form(.dictionary, expression, reading),
                form(.polite, "いいです", "いいです"),
                form(.negative, "よくない", "よくない"),
                form(.past, "よかった", "よかった"),
                form(.teForm, "よくて", "よくて"),
                form(.conditional, "よければ", "よければ"),
                form(.adverbial, "よく", "よく")
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
                form(.connective, expression + "で", reading + "で"),
                form(.conditional, expression + "なら", reading + "なら"),
                form(.adverbial, expression + "に", reading + "に")
            ]
        )
    }

    private func godanVerb(
        _ request: ConjugationGenerationRequest,
        expression: String,
        reading: String
    ) -> GeneratedConjugation? {
        if shouldAvoidLocalGodanGeneration(expression: expression, reading: reading) {
            return nil
        }

        guard let expressionEnding = expression.last,
              let readingEnding = reading.last,
              expressionEnding == readingEnding,
              let endings = godanEndings[expressionEnding] else {
            return nil
        }

        let expressionStem = String(expression.dropLast())
        let readingStem = String(reading.dropLast())
        return generated(
            request,
            conjugationClass: .godanVerb,
            forms: verbForms(
                dictionarySurface: expression,
                dictionaryReading: reading,
                polite: (expressionStem + endings.polite, readingStem + endings.polite),
                negative: (expressionStem + endings.negative, readingStem + endings.negative),
                past: (expressionStem + endings.past, readingStem + endings.past),
                te: (expressionStem + endings.te, readingStem + endings.te),
                conditional: (expressionStem + endings.conditional, readingStem + endings.conditional),
                potential: (expressionStem + endings.potential, readingStem + endings.potential),
                volitional: (expressionStem + endings.volitional, readingStem + endings.volitional),
                imperative: (expressionStem + endings.imperative, readingStem + endings.imperative),
                passive: (expressionStem + endings.passive, readingStem + endings.passive),
                causative: (expressionStem + endings.causative, readingStem + endings.causative),
                causativePassive: (expressionStem + endings.causativePassive, readingStem + endings.causativePassive)
            )
        )
    }

    private func ikuVerb(
        _ request: ConjugationGenerationRequest,
        expression: String,
        reading: String
    ) -> GeneratedConjugation? {
        guard reading == "いく" else {
            return nil
        }

        let usesKanjiSurface = expression == "行く"
        return generated(
            request,
            conjugationClass: .godanVerb,
            forms: verbForms(
                dictionarySurface: expression,
                dictionaryReading: reading,
                polite: (usesKanjiSurface ? "行きます" : "いきます", "いきます"),
                negative: (usesKanjiSurface ? "行かない" : "いかない", "いかない"),
                past: (usesKanjiSurface ? "行った" : "いった", "いった"),
                te: (usesKanjiSurface ? "行って" : "いって", "いって"),
                conditional: (usesKanjiSurface ? "行けば" : "いけば", "いけば"),
                potential: (usesKanjiSurface ? "行ける" : "いける", "いける"),
                volitional: (usesKanjiSurface ? "行こう" : "いこう", "いこう"),
                imperative: (usesKanjiSurface ? "行け" : "いけ", "いけ"),
                passive: (usesKanjiSurface ? "行かれる" : "いかれる", "いかれる"),
                causative: (usesKanjiSurface ? "行かせる" : "いかせる", "いかせる"),
                causativePassive: (usesKanjiSurface ? "行かせられる" : "いかせられる", "いかせられる")
            )
        )
    }

    private func aruVerb(
        _ request: ConjugationGenerationRequest,
        expression: String,
        reading: String
    ) -> GeneratedConjugation {
        generated(
            request,
            conjugationClass: .godanVerb,
            forms: [
                form(.dictionary, expression, reading),
                form(.polite, "あります", "あります"),
                form(.negative, "ない", "ない"),
                form(.past, "あった", "あった"),
                form(.teForm, "あって", "あって"),
                form(.conditional, "あれば", "あれば"),
                form(.volitional, "あろう", "あろう"),
                form(.imperative, "あれ", "あれ")
            ]
        )
    }

    private func verbForms(
        dictionarySurface: String,
        dictionaryReading: String,
        polite: (surface: String, reading: String),
        negative: (surface: String, reading: String),
        past: (surface: String, reading: String),
        te: (surface: String, reading: String),
        conditional: (surface: String, reading: String),
        potential: (surface: String, reading: String),
        volitional: (surface: String, reading: String),
        imperative: (surface: String, reading: String),
        passive: (surface: String, reading: String),
        causative: (surface: String, reading: String),
        causativePassive: (surface: String, reading: String)
    ) -> [ConjugationForm] {
        [
            form(.dictionary, dictionarySurface, dictionaryReading),
            form(.polite, polite.surface, polite.reading),
            form(.negative, negative.surface, negative.reading),
            form(.past, past.surface, past.reading),
            form(.teForm, te.surface, te.reading),
            form(.conditional, conditional.surface, conditional.reading),
            form(.potential, potential.surface, potential.reading),
            form(.volitional, volitional.surface, volitional.reading),
            form(.imperative, imperative.surface, imperative.reading),
            form(.passive, passive.surface, passive.reading),
            form(.causative, causative.surface, causative.reading),
            form(.causativePassive, causativePassive.surface, causativePassive.reading)
        ]
    }

    private func containsAny(_ candidates: Set<String>, in tokens: Set<String>) -> Bool {
        !tokens.isDisjoint(with: candidates)
    }

    private func shouldAvoidLocalGodanGeneration(expression: String, reading: String) -> Bool {
        let unsupportedSpecials: Set<String> = [
            "問う", "請う", "乞う",
            "いらっしゃる", "おっしゃる", "くださる", "なさる", "ござる"
        ]
        return unsupportedSpecials.contains(expression) || unsupportedSpecials.contains(reading)
    }

    /// Only orthographic exceptions belong here. Checking the reading would
    /// reject valid Ichidan homophones such as 着る/きる because 切る is Godan.
    private var knownGodanRuExpressions: Set<String> {
        [
            "帰る", "走る", "入る", "切る", "知る",
            "要る", "減る", "滑る",
            "喋る",
            "参る"
        ]
    }

    private var godanEndings: [Character: GodanEnding] {
        [
            "う": .init(
                polite: "います",
                negative: "わない",
                past: "った",
                te: "って",
                conditional: "えば",
                potential: "える",
                volitional: "おう",
                imperative: "え",
                passive: "われる",
                causative: "わせる",
                causativePassive: "わせられる"
            ),
            "く": .init(
                polite: "きます",
                negative: "かない",
                past: "いた",
                te: "いて",
                conditional: "けば",
                potential: "ける",
                volitional: "こう",
                imperative: "け",
                passive: "かれる",
                causative: "かせる",
                causativePassive: "かせられる"
            ),
            "ぐ": .init(
                polite: "ぎます",
                negative: "がない",
                past: "いだ",
                te: "いで",
                conditional: "げば",
                potential: "げる",
                volitional: "ごう",
                imperative: "げ",
                passive: "がれる",
                causative: "がせる",
                causativePassive: "がせられる"
            ),
            "す": .init(
                polite: "します",
                negative: "さない",
                past: "した",
                te: "して",
                conditional: "せば",
                potential: "せる",
                volitional: "そう",
                imperative: "せ",
                passive: "される",
                causative: "させる",
                causativePassive: "させられる"
            ),
            "つ": .init(
                polite: "ちます",
                negative: "たない",
                past: "った",
                te: "って",
                conditional: "てば",
                potential: "てる",
                volitional: "とう",
                imperative: "て",
                passive: "たれる",
                causative: "たせる",
                causativePassive: "たせられる"
            ),
            "ぬ": .init(
                polite: "にます",
                negative: "なない",
                past: "んだ",
                te: "んで",
                conditional: "ねば",
                potential: "ねる",
                volitional: "のう",
                imperative: "ね",
                passive: "なれる",
                causative: "なせる",
                causativePassive: "なせられる"
            ),
            "ぶ": .init(
                polite: "びます",
                negative: "ばない",
                past: "んだ",
                te: "んで",
                conditional: "べば",
                potential: "べる",
                volitional: "ぼう",
                imperative: "べ",
                passive: "ばれる",
                causative: "ばせる",
                causativePassive: "ばせられる"
            ),
            "む": .init(
                polite: "みます",
                negative: "まない",
                past: "んだ",
                te: "んで",
                conditional: "めば",
                potential: "める",
                volitional: "もう",
                imperative: "め",
                passive: "まれる",
                causative: "ませる",
                causativePassive: "ませられる"
            ),
            "る": .init(
                polite: "ります",
                negative: "らない",
                past: "った",
                te: "って",
                conditional: "れば",
                potential: "れる",
                volitional: "ろう",
                imperative: "れ",
                passive: "られる",
                causative: "らせる",
                causativePassive: "らせられる"
            )
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
            forms: forms
        )
    }

    private func form(_ type: ConjugationFormType, _ surface: String, _ reading: String) -> ConjugationForm {
        ConjugationForm(type: type, surface: surface, reading: reading)
    }
}

private struct GodanEnding {
    let polite: String
    let negative: String
    let past: String
    let te: String
    let conditional: String
    let potential: String
    let volitional: String
    let imperative: String
    let passive: String
    let causative: String
    let causativePassive: String
}
