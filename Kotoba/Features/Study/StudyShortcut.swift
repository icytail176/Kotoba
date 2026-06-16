//
//  StudyShortcut.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import Foundation

enum StudyShortcut: Equatable {
    case showAnswer
    case rate(ReviewRating)
    case speakWord
    case speakExample
    case stopSpeech
    case toggleFavorite
}
