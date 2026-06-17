//
//  ConjugationCacheService.swift
//  Kotoba
//
//  Created by Codex on 2026/6/17.
//

import Foundation
import SwiftData

@MainActor
struct ConjugationCacheService {
    static let schemaVersion = 1

    private let ruleEngine = ConjugationRuleEngine()
    private let validator = ConjugationValidationService()

    func validRecords(for words: [VocabularyWord], in context: ModelContext) throws -> [ConjugationRecord] {
        let wordIDs = Set(words.map(\.id))
        guard !wordIDs.isEmpty else {
            return []
        }

        return try context.fetch(FetchDescriptor<ConjugationRecord>())
            .filter { record in
                guard wordIDs.contains(record.wordID),
                      record.schemaVersion == Self.schemaVersion,
                      record.validationStatus == .valid,
                      !record.markedIncorrect,
                      let word = words.first(where: { $0.id == record.wordID }) else {
                    return false
                }

                return record.sourceFingerprint == fingerprint(for: word)
            }
    }

    func ensureLocalRecord(for word: VocabularyWord, in context: ModelContext, now: Date = Date()) throws -> ConjugationRecord? {
        let expectedFingerprint = fingerprint(for: word)
        if let cached = try context.fetch(FetchDescriptor<ConjugationRecord>()).first(where: {
            $0.wordID == word.id
                && $0.schemaVersion == Self.schemaVersion
                && $0.sourceFingerprint == expectedFingerprint
                && $0.validationStatus == .valid
                && !$0.markedIncorrect
        }) {
            return cached
        }

        guard let generated = ruleEngine.generate(for: word) else {
            return nil
        }

        let request = ConjugationGenerationRequest(
            wordID: word.id,
            expression: word.japanese,
            reading: word.kana,
            meaningChinese: word.chineseMeaning,
            partOfSpeech: word.partOfSpeech
        )
        let status = validator.validate(generated, for: request)
        let record = ConjugationRecord(
            wordID: word.id,
            conjugationClass: generated.conjugationClass,
            forms: generated.forms,
            source: generated.source,
            validationStatus: status,
            modelName: generated.modelName,
            generatedAt: now,
            schemaVersion: Self.schemaVersion,
            sourceFingerprint: expectedFingerprint
        )
        context.insert(record)
        try context.save()
        return status == .valid ? record : nil
    }

    func fingerprint(for word: VocabularyWord) -> String {
        [
            word.japanese,
            word.kana,
            word.partOfSpeech,
            "\(Self.schemaVersion)"
        ].joined(separator: "\u{1F}")
    }
}
