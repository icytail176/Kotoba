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
}
