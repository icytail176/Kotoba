//
//  WordBook.swift
//  Kotoba
//
//  Created by Codex on 2026/6/17.
//

import Foundation
import SwiftData

@Model
final class WordBook {
    @Attribute(.unique) var id: UUID
    var name: String
    var bookDescription: String
    var createdAt: Date
    var updatedAt: Date
    var isBuiltIn: Bool

    @Relationship(deleteRule: .cascade, inverse: \VocabularyWord.wordBook)
    var words: [VocabularyWord]

    init(
        id: UUID = UUID(),
        name: String,
        bookDescription: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isBuiltIn: Bool = false,
        words: [VocabularyWord] = []
    ) {
        self.id = id
        self.name = name
        self.bookDescription = bookDescription
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isBuiltIn = isBuiltIn
        self.words = words
    }
}
