//
//  StudySession.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import Foundation

struct StudySession {
    enum Status: Equatable {
        case ready
        case completed
    }

    struct Item: Identifiable, Equatable {
        enum Kind: Equatable {
            case dueReview
            case newWord
        }

        let id: UUID
        let word: VocabularyWord
        let kind: Kind
        let dueAt: Date

        static func == (lhs: Item, rhs: Item) -> Bool {
            lhs.id == rhs.id && lhs.kind == rhs.kind && lhs.dueAt == rhs.dueAt
        }
    }

    let status: Status
    let items: [Item]
    let newWordLimit: Int
    let newWordsAlreadyIntroducedToday: Int

    var isCompleted: Bool {
        status == .completed
    }
}
