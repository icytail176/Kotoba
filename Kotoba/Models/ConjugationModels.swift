//
//  ConjugationModels.swift
//  Kotoba
//
//  Created by Codex on 2026/6/17.
//

import Foundation

enum ConjugationClass: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case ichidanVerb
    case godanVerb
    case suruVerb
    case kuruVerb
    case iAdjective
    case naAdjective
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:
            return "无活用"
        case .ichidanVerb:
            return "一段动词"
        case .godanVerb:
            return "五段动词"
        case .suruVerb:
            return "サ变动词"
        case .kuruVerb:
            return "カ变动词"
        case .iAdjective:
            return "い形容词"
        case .naAdjective:
            return "な形容词"
        case .unknown:
            return "未知"
        }
    }
}

enum ConjugationFormType: String, Codable, CaseIterable, Identifiable, Sendable {
    case dictionary
    case polite
    case negative
    case past
    case teForm
    case connective

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dictionary:
            return "辞书形"
        case .polite:
            return "ます形"
        case .negative:
            return "否定形"
        case .past:
            return "过去形"
        case .teForm:
            return "て形"
        case .connective:
            return "连接形"
        }
    }
}

enum ConjugationSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case localRule
    case lmStudio
    case manual

    var id: String { rawValue }
}

enum ConjugationValidationStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case valid
    case needsReview
    case invalid

    var id: String { rawValue }
}

struct ConjugationForm: Codable, Equatable, Sendable {
    let type: ConjugationFormType
    let surface: String
    let reading: String
}

struct ConjugationGenerationRequest: Codable, Equatable, Sendable {
    let wordID: UUID
    let expression: String
    let reading: String
    let meaningChinese: String
    let partOfSpeech: String
}

struct GeneratedConjugation: Codable, Equatable, Sendable {
    let wordID: UUID
    let expression: String
    let reading: String
    let conjugationClass: ConjugationClass
    let forms: [ConjugationForm]
    let source: ConjugationSource
    let modelName: String
}

struct ProviderStatus: Equatable, Sendable {
    let isAvailable: Bool
    let message: String
}
