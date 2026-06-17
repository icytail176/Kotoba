//
//  ConjugationRecord.swift
//  Kotoba
//
//  Created by Codex on 2026/6/17.
//

import Foundation
import SwiftData

@Model
final class ConjugationRecord {
    @Attribute(.unique) var id: UUID
    var wordID: UUID
    private var conjugationClassRawValue: String
    private var sourceRawValue: String
    private var validationStatusRawValue: String
    private var formsData: Data
    var modelName: String
    var generatedAt: Date
    var schemaVersion: Int
    var sourceFingerprint: String
    var markedIncorrect: Bool

    var conjugationClass: ConjugationClass {
        get { ConjugationClass(rawValue: conjugationClassRawValue) ?? .unknown }
        set { conjugationClassRawValue = newValue.rawValue }
    }

    var source: ConjugationSource {
        get { ConjugationSource(rawValue: sourceRawValue) ?? .manual }
        set { sourceRawValue = newValue.rawValue }
    }

    var validationStatus: ConjugationValidationStatus {
        get { ConjugationValidationStatus(rawValue: validationStatusRawValue) ?? .needsReview }
        set { validationStatusRawValue = newValue.rawValue }
    }

    var forms: [ConjugationForm] {
        get {
            (try? JSONDecoder().decode([ConjugationForm].self, from: formsData)) ?? []
        }
        set {
            formsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    init(
        id: UUID = UUID(),
        wordID: UUID,
        conjugationClass: ConjugationClass,
        forms: [ConjugationForm],
        source: ConjugationSource,
        validationStatus: ConjugationValidationStatus,
        modelName: String = "",
        generatedAt: Date = Date(),
        schemaVersion: Int = 1,
        sourceFingerprint: String,
        markedIncorrect: Bool = false
    ) {
        self.id = id
        self.wordID = wordID
        self.conjugationClassRawValue = conjugationClass.rawValue
        self.sourceRawValue = source.rawValue
        self.validationStatusRawValue = validationStatus.rawValue
        self.formsData = (try? JSONEncoder().encode(forms)) ?? Data()
        self.modelName = modelName
        self.generatedAt = generatedAt
        self.schemaVersion = schemaVersion
        self.sourceFingerprint = sourceFingerprint
        self.markedIncorrect = markedIncorrect
    }
}
