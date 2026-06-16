//
//  ReviewRating.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import Foundation

enum ReviewRating: String, CaseIterable, Codable, Identifiable, Sendable {
    case again
    case hard
    case good
    case easy

    var id: String { rawValue }
}
