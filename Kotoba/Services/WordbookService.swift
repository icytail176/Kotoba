//
//  WordBookService.swift
//  Kotoba
//
//  Created by Codex on 2026/6/17.
//

import Foundation
import SwiftData

struct WordBookSummary: Identifiable, Equatable {
    let id: UUID
    let name: String
    let bookDescription: String
    let totalWordCount: Int
    let newWordCount: Int
    let learningWordCount: Int
    let reviewWordCount: Int
    let dueReviewCount: Int
    let createdAt: Date
    let isSelected: Bool
}

struct WordBookDraft: Equatable {
    var id: UUID?
    var name = ""
    var bookDescription = ""

    init() {}

    init(wordBook: WordBook) {
        id = wordBook.id
        name = wordBook.name
        bookDescription = wordBook.bookDescription
    }
}

enum WordbookFilterValue: String, CaseIterable, Identifiable {
    case all

    var id: String { rawValue }
}

struct WordbookFilters: Equatable {
    static let currentWordBookValue = "__current_word_book__"

    var wordBookID = currentWordBookValue
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
    let wordBooks: [WordBookOption]
    let jlptLevels: [String]
    let partsOfSpeech: [String]
    let tags: [String]
    let learningStates: [LearningState]
}

struct WordBookOption: Identifiable, Equatable {
    let id: UUID
    let name: String
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
    private let partOfSpeechTokenizer = PartOfSpeechTokenizer()

    func fetchWords(in context: ModelContext, wordBookID: UUID? = nil) throws -> [VocabularyWord] {
        var descriptor = FetchDescriptor<VocabularyWord>(
            sortBy: [
                SortDescriptor(\.japanese, order: .forward),
                SortDescriptor(\.kana, order: .forward)
            ]
        )
        descriptor.includePendingChanges = true

        let words = try context.fetch(descriptor)
        guard let wordBookID else {
            return words
        }

        return words.filter { $0.wordBook?.id == wordBookID }
    }

    func filter(
        _ words: [VocabularyWord],
        using filters: WordbookFilters,
        currentWordBookID: UUID?
    ) -> [VocabularyWord] {
        let searchText = filters.searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return words.filter { word in
            switch filters.wordBookID {
            case WordbookFilterValue.all.rawValue:
                break
            case WordbookFilters.currentWordBookValue:
                guard let currentWordBookID, word.wordBook?.id == currentWordBookID else {
                    return false
                }
            default:
                guard let filterWordBookID = UUID(uuidString: filters.wordBookID),
                      word.wordBook?.id == filterWordBookID else {
                    return false
                }
            }

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

            if filters.partOfSpeech != WordbookFilterValue.all.rawValue,
               !partOfSpeechTokenizer.containsToken(filters.partOfSpeech, in: word.partOfSpeech) {
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

    func makeOptionSets(from words: [VocabularyWord], wordBooks: [WordBook] = []) -> WordbookOptionSets {
        let jlptLevels = sortedUnique(words.map(\.jlptLevel))
        let partsOfSpeech = sortedUnique(words.flatMap { partOfSpeechTokenizer.tokens(from: $0.partOfSpeech) })
        let tags = sortedUnique(words.flatMap(\.tags))
        let states = LearningState.allCases.filter { state in
            words.contains { $0.progress?.state == state }
        }

        return WordbookOptionSets(
            wordBooks: wordBooks.map { WordBookOption(id: $0.id, name: $0.name) },
            jlptLevels: jlptLevels,
            partsOfSpeech: partsOfSpeech,
            tags: tags,
            learningStates: states
        )
    }

    @discardableResult
    func createWord(
        from draft: WordEditorDraft,
        wordBook: WordBook,
        in context: ModelContext,
        now: Date = Date()
    ) throws -> VocabularyWord {
        let sanitizedDraft = try validateAndSanitize(draft)
        let word = VocabularyWord(
            japanese: sanitizedDraft.expression,
            kana: sanitizedDraft.reading,
            chineseMeaning: sanitizedDraft.meaningChinese,
            partOfSpeech: partOfSpeechTokenizer.normalized(sanitizedDraft.partOfSpeech),
            jlptLevel: sanitizedDraft.jlptLevel,
            exampleJapanese: sanitizedDraft.exampleJapanese,
            exampleChinese: sanitizedDraft.exampleChinese,
            tags: parseTags(sanitizedDraft.tagsText),
            createdAt: now,
            updatedAt: now,
            isFavorite: sanitizedDraft.isFavorite,
            wordBook: wordBook
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
            word.partOfSpeech = partOfSpeechTokenizer.normalized(sanitizedDraft.partOfSpeech)
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
            let records = try context.fetch(FetchDescriptor<ConjugationRecord>())
                .filter { $0.wordID == word.id }
            for record in records {
                context.delete(record)
            }
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
        sanitizedDraft.partOfSpeech = partOfSpeechTokenizer.normalized(draft.partOfSpeech)
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

enum WordBookValidationError: LocalizedError, Equatable {
    case missingName

    var errorDescription: String? {
        switch self {
        case .missingName:
            return "词书名称必填。"
        }
    }
}

@MainActor
struct WordBookService {
    static let migratedDefaultBookName = "默认词书"

    func migrateLegacyWordsIfNeeded(in context: ModelContext, now: Date = Date()) throws {
        let words = try context.fetch(FetchDescriptor<VocabularyWord>())
        let legacyWords = words.filter { $0.wordBook == nil }

        guard !legacyWords.isEmpty else {
            return
        }

        let wordBook = try migratedDefaultBook(in: context, now: now)
        for word in legacyWords {
            word.wordBook = wordBook

            if !wordBook.words.contains(where: { $0.id == word.id }) {
                wordBook.words.append(word)
            }
        }

        wordBook.updatedAt = now
        try context.save()
    }

    func fetchWordBooks(in context: ModelContext) throws -> [WordBook] {
        let descriptor = FetchDescriptor<WordBook>(
            sortBy: [
                SortDescriptor(\.createdAt, order: .forward),
                SortDescriptor(\.name, order: .forward)
            ]
        )
        return try context.fetch(descriptor)
    }

    func resolveSelectedWordBook(
        in context: ModelContext,
        selectedIDString: String?
    ) throws -> WordBook? {
        let books = try fetchWordBooks(in: context)
        guard !books.isEmpty else {
            return nil
        }

        if let selectedIDString,
           let selectedID = UUID(uuidString: selectedIDString),
           let selectedBook = books.first(where: { $0.id == selectedID }) {
            return selectedBook
        }

        return books.first
    }

    func summaries(
        in context: ModelContext,
        selectedIDString: String?,
        now: Date = Date()
    ) throws -> [WordBookSummary] {
        let books = try fetchWordBooks(in: context)
        let selectedID = selectedIDString.flatMap(UUID.init(uuidString:))

        return books.map { book in
            summary(for: book, selectedID: selectedID, now: now)
        }
    }

    func summary(
        for book: WordBook,
        selectedID: UUID?,
        now: Date = Date()
    ) -> WordBookSummary {
        let activeWords = book.words.filter { !$0.isArchived }
        let newWordCount = activeWords.filter { $0.progress?.state == .new }.count
        let learningWordCount = activeWords.filter { word in
            guard let state = word.progress?.state else {
                return false
            }

            return state == .learning || state == .relearning
        }.count
        let reviewWordCount = activeWords.filter { $0.progress?.state == .review }.count
        let dueReviewCount = activeWords.filter { word in
            guard let progress = word.progress else {
                return false
            }

            return progress.state != .new
                && progress.state != .suspended
                && progress.dueAt <= now
        }.count

        return WordBookSummary(
            id: book.id,
            name: book.name,
            bookDescription: book.bookDescription,
            totalWordCount: activeWords.count,
            newWordCount: newWordCount,
            learningWordCount: learningWordCount,
            reviewWordCount: reviewWordCount,
            dueReviewCount: dueReviewCount,
            createdAt: book.createdAt,
            isSelected: selectedID == book.id
        )
    }

    @discardableResult
    func createWordBook(
        from draft: WordBookDraft,
        in context: ModelContext,
        now: Date = Date()
    ) throws -> WordBook {
        let sanitizedDraft = try validateAndSanitize(draft)
        let wordBook = WordBook(
            name: sanitizedDraft.name,
            bookDescription: sanitizedDraft.bookDescription,
            createdAt: now,
            updatedAt: now
        )

        do {
            context.insert(wordBook)
            try context.save()
            return wordBook
        } catch {
            context.rollback()
            throw error
        }
    }

    func updateWordBook(
        _ wordBook: WordBook,
        from draft: WordBookDraft,
        in context: ModelContext,
        now: Date = Date()
    ) throws {
        do {
            let sanitizedDraft = try validateAndSanitize(draft)
            wordBook.name = sanitizedDraft.name
            wordBook.bookDescription = sanitizedDraft.bookDescription
            wordBook.updatedAt = now
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func deleteWordBook(_ wordBook: WordBook, in context: ModelContext) throws {
        do {
            let wordIDs = Set(wordBook.words.map(\.id))
            let records = try context.fetch(FetchDescriptor<ConjugationRecord>())
                .filter { wordIDs.contains($0.wordID) }
            for record in records {
                context.delete(record)
            }

            context.delete(wordBook)

            let orphanProgress = try context.fetch(FetchDescriptor<LearningProgress>())
                .filter { $0.word == nil }
            let orphanLogs = try context.fetch(FetchDescriptor<ReviewLog>())
                .filter { $0.word == nil }

            for progress in orphanProgress {
                context.delete(progress)
            }

            for log in orphanLogs {
                context.delete(log)
            }

            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func validateAndSanitize(_ draft: WordBookDraft) throws -> WordBookDraft {
        var sanitizedDraft = draft
        sanitizedDraft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitizedDraft.bookDescription = draft.bookDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        if sanitizedDraft.name.isEmpty {
            throw WordBookValidationError.missingName
        }

        return sanitizedDraft
    }

    private func migratedDefaultBook(in context: ModelContext, now: Date) throws -> WordBook {
        let books = try fetchWordBooks(in: context)
        if let existingBook = books.first(where: { $0.name == Self.migratedDefaultBookName }) {
            return existingBook
        }

        let wordBook = WordBook(
            name: Self.migratedDefaultBookName,
            bookDescription: "从旧版本自动迁移的本地词条。",
            createdAt: now,
            updatedAt: now
        )
        context.insert(wordBook)
        return wordBook
    }
}
