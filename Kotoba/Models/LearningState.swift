//
//  LearningState.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import Foundation

enum LearningState: String, CaseIterable, Codable, Identifiable, Sendable {
    case new
    case learning
    case review
    case relearning
    case suspended

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .new:
            return "新词"
        case .learning:
            return "学习中"
        case .review:
            return "复习中"
        case .relearning:
            return "重新学习"
        case .suspended:
            return "熟练"
        }
    }
}
