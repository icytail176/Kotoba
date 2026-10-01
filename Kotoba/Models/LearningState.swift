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
        LearningStatePresentation.name(for: self)
    }
}

enum LearningStatePresentation {
    static func name(for state: LearningState?) -> String {
        switch state {
        case nil, .new:
            return "未学习"
        case .learning, .relearning, .review:
            return "复习中"
        case .suspended:
            return "已熟练"
        }
    }

    static func isReviewing(_ state: LearningState?) -> Bool {
        guard let state else { return false }
        return state == .learning || state == .relearning || state == .review
    }
}
