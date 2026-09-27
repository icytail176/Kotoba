//
//  WordEditorPreviewService.swift
//  Kotoba
//
//  Created by Codex on 2026/6/18.
//

import Foundation

struct WordEditorPreview: Equatable {
    let normalizedPartOfSpeechTokens: [String]
    let conjugationClass: ConjugationClass
    let isConjugatable: Bool
    let requiresManualReview: Bool
    let forms: [ConjugationForm]
    let warnings: [String]
}

struct WordEditorPreviewService {
    private let tokenizer = PartOfSpeechTokenizer()
    private let ruleEngine = ConjugationRuleEngine()

    func makePreview(from draft: WordEditorDraft) -> WordEditorPreview {
        let normalizedPartOfSpeech = tokenizer.normalized(draft.partOfSpeech)
        let tokens = tokenizer.tokens(from: normalizedPartOfSpeech)
        let word = VocabularyWord(
            japanese: draft.expression.trimmingCharacters(in: .whitespacesAndNewlines),
            kana: draft.reading.trimmingCharacters(in: .whitespacesAndNewlines),
            chineseMeaning: draft.meaningChinese.trimmingCharacters(in: .whitespacesAndNewlines),
            partOfSpeech: normalizedPartOfSpeech,
            jlptLevel: draft.jlptLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        let generated = ruleEngine.generate(for: word)
        let isConjugatable = mayNeedConjugation(tokens)
        var warnings = makeWarnings(for: word, tokens: tokens, generated: generated, isConjugatable: isConjugatable)

        if tokens.isEmpty {
            warnings.append("词性为空，无法进行筛选或活用判断。")
        }

        return WordEditorPreview(
            normalizedPartOfSpeechTokens: tokens,
            conjugationClass: generated?.conjugationClass ?? (isConjugatable ? .unknown : .none),
            isConjugatable: isConjugatable,
            requiresManualReview: isConjugatable && generated == nil,
            forms: generated?.forms.filter { $0.type != .dictionary }.prefix(6).map { $0 } ?? [],
            warnings: warnings
        )
    }

    private func mayNeedConjugation(_ tokens: [String]) -> Bool {
        let conjugatableTokens: Set<String> = [
            "动词", "動詞", "一段动词", "一段動詞", "五段动词", "五段動詞",
            "サ变动词", "サ変動詞", "する动词", "する動詞", "カ变动词", "カ変動詞",
            "形容词", "形容詞", "い形容词", "い形容詞", "な形容词", "な形容詞"
        ]
        return tokens.contains { conjugatableTokens.contains($0) }
    }

    private func makeWarnings(
        for word: VocabularyWord,
        tokens: [String],
        generated: GeneratedConjugation?,
        isConjugatable: Bool
    ) -> [String] {
        var warnings: [String] = []

        if tokens.contains("动词") || tokens.contains("動詞") {
            warnings.append("词性只有“动词”，请标注为五段动词、一段动词、サ变动词或カ变动词。")
        }

        if tokens.contains("形容词") || tokens.contains("形容詞") {
            warnings.append("词性只有“形容词”，请标注为い形容词或な形容词。")
        }

        if isNaAdjectiveRisk(word: word, tokens: tokens) {
            warnings.append("\(word.japanese) 以 い 结尾，但常见为な形容词，请确认不要误标为い形容词。")
        }

        if isConjugatable, generated == nil {
            warnings.append("当前输入无法生成可信本地活用，保存后需要人工检查。")
        }

        return warnings
    }

    private func isNaAdjectiveRisk(word: VocabularyWord, tokens: [String]) -> Bool {
        guard tokens.contains("い形容词") || tokens.contains("い形容詞") else {
            return false
        }

        let riskyWords = Set(["きれい", "綺麗", "嫌い", "きらい", "有名", "ゆうめい"])
        return riskyWords.contains(word.japanese) || riskyWords.contains(word.kana)
    }
}
