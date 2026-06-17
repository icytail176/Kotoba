//
//  VocabularyWord.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import Foundation
import SwiftData

@Model
final class VocabularyWord {
    @Attribute(.unique) var id: UUID
    var japanese: String
    var kana: String
    var chineseMeaning: String
    var partOfSpeech: String
    var jlptLevel: String
    var exampleJapanese: String
    var exampleChinese: String
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool
    var isFavorite: Bool

    var wordBook: WordBook?

    @Relationship(deleteRule: .cascade, inverse: \LearningProgress.word)
    var progress: LearningProgress?

    @Relationship(deleteRule: .cascade, inverse: \ReviewLog.word)
    var reviewLogs: [ReviewLog]

    init(
        id: UUID = UUID(),
        japanese: String,
        kana: String,
        chineseMeaning: String,
        partOfSpeech: String = "",
        jlptLevel: String,
        exampleJapanese: String = "",
        exampleChinese: String = "",
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isArchived: Bool = false,
        isFavorite: Bool = false,
        wordBook: WordBook? = nil,
        progress: LearningProgress? = nil,
        reviewLogs: [ReviewLog] = []
    ) {
        self.id = id
        self.japanese = japanese
        self.kana = kana
        self.chineseMeaning = chineseMeaning
        self.partOfSpeech = partOfSpeech
        self.jlptLevel = jlptLevel
        self.exampleJapanese = exampleJapanese
        self.exampleChinese = exampleChinese
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
        self.isFavorite = isFavorite
        self.wordBook = wordBook
        self.progress = progress
        self.reviewLogs = reviewLogs
    }
}
