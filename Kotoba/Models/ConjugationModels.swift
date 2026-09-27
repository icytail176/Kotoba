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
    case conditional
    case potential
    case volitional
    case imperative
    case passive
    case causative
    case causativePassive
    case adverbial

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
        case .conditional:
            return "条件形"
        case .potential:
            return "可能形"
        case .volitional:
            return "意志形"
        case .imperative:
            return "命令形"
        case .passive:
            return "被动形"
        case .causative:
            return "使役形"
        case .causativePassive:
            return "使役被动形"
        case .adverbial:
            return "副词形"
        }
    }
}

struct ConjugationForm: Codable, Equatable, Sendable {
    let type: ConjugationFormType
    let surface: String
    let reading: String
    let allowsSpelling: Bool

    init(
        type: ConjugationFormType,
        surface: String,
        reading: String,
        allowsSpelling: Bool = true
    ) {
        self.type = type
        self.surface = surface
        self.reading = reading
        self.allowsSpelling = allowsSpelling
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case surface
        case reading
        case allowsSpelling
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(ConjugationFormType.self, forKey: .type)
        surface = try container.decode(String.self, forKey: .surface)
        reading = try container.decode(String.self, forKey: .reading)
        allowsSpelling = try container.decodeIfPresent(Bool.self, forKey: .allowsSpelling) ?? true
    }
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
}
