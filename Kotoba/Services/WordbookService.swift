//
//  WordbookService.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import Foundation
import SwiftData

enum WordbookFilterValue: String, CaseIterable, Identifiable {
    case all

    var id: String { rawValue }
}

struct WordbookFilters: Equatable {
    var searchText = ""
    var jlptLevel = WordbookFilterValue.all.rawValue
    var partOfSpeech = WordbookFilterValue.all.rawValue
    var tag = WordbookFilterValue.all.rawValue
    var learningState = WordbookFilterValue.all.rawValue
    var favoritesOnly = false
}

struct WordEditorDraft: Equatable {
    var id: UUID?
    var expression = ""
    var reading = ""
    var meaningChinese = ""
    var partOfSpeech = ""
    var exampleJapanese = ""
    var exampleChinese = ""
    var jlptLevel = ""
    var tagsText = ""
    var isFavorite = false

    init() {}

    init(word: VocabularyWord) {
        id = word.id
        expression = word.japanese
        reading = word.kana
        meaningChinese = word.chineseMeaning
        partOfSpeech = word.partOfSpeech
        exampleJapanese = word.exampleJapanese
        exampleChinese = word.exampleChinese
        jlptLevel = word.jlptLevel
        tagsText = word.tags.joined(separator: ";")
        isFavorite = word.isFavorite
    }
}

struct WordbookOptionSets: Equatable {
    let jlptLevels: [String]
    let partsOfSpeech: [String]
    let tags: [String]
    let learningStates: [LearningState]
}

enum WordbookValidationError: LocalizedError, Equatable {
    case missingRequiredFields([String])

    var errorDescription: String? {
        switch self {
        case .missingRequiredFields(let fields):
            return "\(fields.joined(separator: "、")) 必填。"
        }
    }
}

@MainActor
struct WordbookService {
    func fetchWords(in context: ModelContext) throws -> [VocabularyWord] {
        var descriptor = FetchDescriptor<VocabularyWord>(
            sortBy: [
                SortDescriptor(\.japanese, order: .forward),
                SortDescriptor(\.kana, order: .forward)
            ]
        )
        descriptor.includePendingChanges = true

        return try context.fetch(descriptor)
    }

    func filter(_ words: [VocabularyWord], using filters: WordbookFilters) -> [VocabularyWord] {
        let searchText = filters.searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return words.filter { word in
            if !searchText.isEmpty {
                let matchesSearch = word.japanese.localizedCaseInsensitiveContains(searchText)
                    || word.kana.localizedCaseInsensitiveContains(searchText)
                    || word.chineseMeaning.localizedCaseInsensitiveContains(searchText)
                if !matchesSearch {
                    return false
                }
            }

            if filters.jlptLevel != WordbookFilterValue.all.rawValue, word.jlptLevel != filters.jlptLevel {
                return false
            }

            if filters.partOfSpeech != WordbookFilterValue.all.rawValue, word.partOfSpeech != filters.partOfSpeech {
                return false
            }

            if filters.tag != WordbookFilterValue.all.rawValue, !word.tags.contains(filters.tag) {
                return false
            }

            if filters.favoritesOnly, !word.isFavorite {
                return false
            }

            if filters.learningState != WordbookFilterValue.all.rawValue {
                guard word.progress?.state.rawValue == filters.learningState else {
                    return false
                }
            }

            return true
        }
    }

    func makeOptionSets(from words: [VocabularyWord]) -> WordbookOptionSets {
        let jlptLevels = sortedUnique(words.map(\.jlptLevel))
        let partsOfSpeech = sortedUnique(words.map(\.partOfSpeech))
        let tags = sortedUnique(words.flatMap(\.tags))
        let states = LearningState.allCases.filter { state in
            words.contains { $0.progress?.state == state }
        }

        return WordbookOptionSets(
            jlptLevels: jlptLevels,
            partsOfSpeech: partsOfSpeech,
            tags: tags,
            learningStates: states
        )
    }

    @discardableResult
    func createWord(from draft: WordEditorDraft, in context: ModelContext, now: Date = Date()) throws -> VocabularyWord {
        let sanitizedDraft = try validateAndSanitize(draft)
        let word = VocabularyWord(
            japanese: sanitizedDraft.expression,
            kana: sanitizedDraft.reading,
            chineseMeaning: sanitizedDraft.meaningChinese,
            partOfSpeech: sanitizedDraft.partOfSpeech,
            jlptLevel: sanitizedDraft.jlptLevel,
            exampleJapanese: sanitizedDraft.exampleJapanese,
            exampleChinese: sanitizedDraft.exampleChinese,
            tags: parseTags(sanitizedDraft.tagsText),
            createdAt: now,
            updatedAt: now,
            isFavorite: sanitizedDraft.isFavorite
        )
        word.progress = LearningProgress(
            state: .new,
            dueAt: now,
            createdAt: now,
            updatedAt: now,
            word: word
        )
        do {
            context.insert(word)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        return word
    }

    func updateWord(_ word: VocabularyWord, from draft: WordEditorDraft, in context: ModelContext, now: Date = Date()) throws {
        do {
            let sanitizedDraft = try validateAndSanitize(draft)
            word.japanese = sanitizedDraft.expression
            word.kana = sanitizedDraft.reading
            word.chineseMeaning = sanitizedDraft.meaningChinese
            word.partOfSpeech = sanitizedDraft.partOfSpeech
            word.exampleJapanese = sanitizedDraft.exampleJapanese
            word.exampleChinese = sanitizedDraft.exampleChinese
            word.jlptLevel = sanitizedDraft.jlptLevel
            word.tags = parseTags(sanitizedDraft.tagsText)
            word.isFavorite = sanitizedDraft.isFavorite
            word.updatedAt = now
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func deleteWord(_ word: VocabularyWord, in context: ModelContext) throws {
        do {
            context.delete(word)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func resetProgress(for word: VocabularyWord, in context: ModelContext, now: Date = Date()) throws {
        do {
            if let progress = word.progress {
                progress.state = .new
                progress.dueAt = now
                progress.intervalDays = 0
                progress.reviewCount = 0
                progress.lapseCount = 0
                progress.lastReviewedAt = nil
                progress.updatedAt = now
            } else {
                word.progress = LearningProgress(
                    state: .new,
                    dueAt: now,
                    createdAt: now,
                    updatedAt: now,
                    word: word
                )
            }

            for log in Array(word.reviewLogs) {
                context.delete(log)
            }
            word.reviewLogs.removeAll()
            word.updatedAt = now
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func validateAndSanitize(_ draft: WordEditorDraft) throws -> WordEditorDraft {
        var sanitizedDraft = draft
        sanitizedDraft.expression = draft.expression.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitizedDraft.reading = draft.reading.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitizedDraft.meaningChinese = draft.meaningChinese.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitizedDraft.partOfSpeech = draft.partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitizedDraft.exampleJapanese = draft.exampleJapanese.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitizedDraft.exampleChinese = draft.exampleChinese.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitizedDraft.jlptLevel = draft.jlptLevel.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        sanitizedDraft.tagsText = draft.tagsText.trimmingCharacters(in: .whitespacesAndNewlines)

        var missingFields: [String] = []
        if sanitizedDraft.expression.isEmpty {
            missingFields.append("日语单词")
        }
        if sanitizedDraft.reading.isEmpty {
            missingFields.append("假名")
        }
        if sanitizedDraft.meaningChinese.isEmpty {
            missingFields.append("中文释义")
        }

        if !missingFields.isEmpty {
            throw WordbookValidationError.missingRequiredFields(missingFields)
        }

        return sanitizedDraft
    }

    private func parseTags(_ rawValue: String) -> [String] {
        var seenTags = Set<String>()
        var tags: [String] = []

        for tag in rawValue.split(separator: ";", omittingEmptySubsequences: true) {
            let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTag.isEmpty, !seenTags.contains(trimmedTag) else {
                continue
            }

            seenTags.insert(trimmedTag)
            tags.append(trimmedTag)
        }

        return tags
    }

    private func sortedUnique(_ values: [String]) -> [String] {
        Array(
            Set(
                values
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
