//
//  ConjugationValidationService.swift
//  Kotoba
//
//  Created by Codex on 2026/6/17.
//

import Foundation

struct ConjugationValidationService {
    func validate(
        _ generated: GeneratedConjugation,
        for request: ConjugationGenerationRequest
    ) -> ConjugationValidationStatus {
        guard generated.wordID == request.wordID,
              generated.expression == request.expression,
              generated.reading == request.reading,
              generated.conjugationClass != .unknown,
              !generated.forms.isEmpty else {
            return .invalid
        }

        var seenTypes = Set<ConjugationFormType>()
        for form in generated.forms {
            guard seenTypes.insert(form.type).inserted,
                  !form.surface.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !form.reading.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .invalid
            }

            if form.surface.contains("するする") || form.reading.contains("するする") {
                return .invalid
            }
        }

        guard generated.forms.contains(where: {
            $0.type == .dictionary
                && $0.surface == request.expression
                && $0.reading == request.reading
        }) else {
            return .needsReview
        }

        return .valid
    }
}
