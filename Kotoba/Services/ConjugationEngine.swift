//
//  ConjugationEngine.swift
//  Kotoba
//
//  Created by Codex on 2026/6/18.
//

import Foundation

struct ConjugationEngine {
    private let ruleEngine = ConjugationRuleEngine()

    func generate(for word: VocabularyWord) -> GeneratedConjugation? {
        ruleEngine.generate(for: word)
    }

    func generate(for request: ConjugationGenerationRequest) -> GeneratedConjugation? {
        ruleEngine.generate(for: request)
    }

    func generate(
        for request: ConjugationGenerationRequest,
        forcedClass: ConjugationClass
    ) -> GeneratedConjugation? {
        ruleEngine.generate(for: request, forcedClass: forcedClass)
    }

}
