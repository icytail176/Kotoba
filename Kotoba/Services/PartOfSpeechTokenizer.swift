//
//  PartOfSpeechTokenizer.swift
//  Kotoba
//
//  Created by Codex on 2026/6/17.
//

import Foundation

struct PartOfSpeechTokenizer {
    func tokens(from rawValue: String) -> [String] {
        var seen = Set<String>()
        var tokens: [String] = []

        for rawToken in rawValue.split(separator: "/", omittingEmptySubsequences: false) {
            let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty, !seen.contains(token) else {
                continue
            }

            seen.insert(token)
            tokens.append(token)
        }

        return tokens
    }

    func normalized(_ rawValue: String) -> String {
        tokens(from: rawValue).joined(separator: "/")
    }

    func containsToken(_ token: String, in rawValue: String) -> Bool {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            return false
        }

        return tokens(from: rawValue).contains(normalizedToken)
    }
}
