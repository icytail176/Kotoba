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

struct WordBookSummaryCounts: Equatable, Sendable {
    var totalWordCount = 0
    var newWordCount = 0
    var learningWordCount = 0
    var reviewWordCount = 0
    var dueReviewCount = 0

    nonisolated init(
        totalWordCount: Int = 0,
        newWordCount: Int = 0,
        learningWordCount: Int = 0,
        reviewWordCount: Int = 0,
        dueReviewCount: Int = 0
    ) {
        self.totalWordCount = totalWordCount
        self.newWordCount = newWordCount
        self.learningWordCount = learningWordCount
        self.reviewWordCount = reviewWordCount
        self.dueReviewCount = dueReviewCount
    }

    nonisolated mutating func include(_ word: VocabularyWord, now: Date) {
        totalWordCount += 1

        guard let progress = word.progress else {
            return
        }

        switch progress.state {
        case .new:
            newWordCount += 1
        case .learning, .relearning:
            learningWordCount += 1
        case .review:
            reviewWordCount += 1
        case .suspended:
            break
        }

        if StudyDuePolicy.isDue(state: progress.state, dueAt: progress.dueAt, now: now) {
            dueReviewCount += 1
        }
    }
}

struct WordBookRelearnSummary: Equatable {
    let name: String
    let totalWordCount: Int
    let learnedWordCount: Int
    let dueReviewCount: Int
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

struct WordbookFilterResult {
    let visibleWords: [VocabularyWord]
    let matchingCount: Int
    let selectedWordMatches: Bool
}

struct WordbookRowViewData: Identifiable, Equatable, Sendable {
    let id: UUID
    let expression: String
    let reading: String
    let meaningChinese: String
    let jlptLevel: String
    let partOfSpeech: String
    let learningState: LearningState?
    let isFavorite: Bool

    init(word: VocabularyWord) {
        id = word.id
        expression = word.japanese
        reading = word.kana
        meaningChinese = word.chineseMeaning
        jlptLevel = word.jlptLevel
        partOfSpeech = word.partOfSpeech
        learningState = word.progress?.state
        isFavorite = word.isFavorite
    }

    var learningStateDisplayName: String {
        learningState?.displayName ?? "-"
    }
}

struct WordbookPage: Equatable, Sendable {
    let rows: [WordbookRowViewData]
    let matchingCount: Int
    let isMatchingCountExact: Bool
    let hasNextPage: Bool
}

struct WordBookOption: Identifiable, Equatable {
    let id: UUID
    let name: String
}

enum WordbookValidationError: LocalizedError, Equatable {
    case missingRequiredFields([String])
    case duplicateWord

    var errorDescription: String? {
        switch self {
        case .missingRequiredFields(let fields):
            return "\(fields.joined(separator: "、")) 必填。"
        case .duplicateWord:
            return "该词书中已存在相同单词和读音。"
        }
    }
}

@MainActor
struct WordbookService {
    private let partOfSpeechTokenizer = PartOfSpeechTokenizer()

    func fetchWords(in context: ModelContext, wordBookID: UUID? = nil) throws -> [VocabularyWord] {
        var descriptor: FetchDescriptor<VocabularyWord>
        if let wordBookID {
            descriptor = FetchDescriptor<VocabularyWord>(
                predicate: #Predicate { word in
                    word.wordBook?.id == wordBookID && !word.isArchived
                },
                sortBy: [
                    SortDescriptor(\.japanese, order: .forward),
                    SortDescriptor(\.kana, order: .forward)
                ]
            )
        } else {
            descriptor = FetchDescriptor<VocabularyWord>(
                predicate: #Predicate { word in
                    !word.isArchived
                },
                sortBy: [
                    SortDescriptor(\.japanese, order: .forward),
                    SortDescriptor(\.kana, order: .forward)
                ]
            )
        }
        descriptor.includePendingChanges = true
        return try context.fetch(descriptor)
    }

    func fetchPreviewWords(
        in context: ModelContext,
        wordBookID: UUID,
        limit: Int
    ) throws -> [VocabularyWord] {
        var descriptor = FetchDescriptor<VocabularyWord>(
            predicate: #Predicate { word in
                word.wordBook?.id == wordBookID && !word.isArchived
            },
            sortBy: [
                SortDescriptor(\.japanese, order: .forward),
                SortDescriptor(\.kana, order: .forward)
            ]
        )
        descriptor.fetchLimit = max(0, limit)
        descriptor.includePendingChanges = true
        return try context.fetch(descriptor)
    }

    func fetchWord(
        id: UUID,
        in context: ModelContext
    ) throws -> VocabularyWord? {
        var descriptor = FetchDescriptor<VocabularyWord>(
            predicate: #Predicate { word in
                word.id == id && !word.isArchived
            }
        )
        descriptor.fetchLimit = 1
        descriptor.includePendingChanges = true
        let words = try context.fetch(descriptor)
        PerformanceTrace.fetch("Wordbook detail fetch", count: words.count)
        return words.first
    }

    func fetchWordPage(
        in context: ModelContext,
        scopedWordBookID: UUID?,
        filters: WordbookFilters,
        offset: Int,
        limit: Int
    ) throws -> WordbookPage {
        let offset = max(0, offset)
        let limit = max(1, limit)
        let needsPostFetchFilter = needsPostFetchFilter(filters)

        if needsPostFetchFilter {
            return try fetchPostFilteredWordPage(
                in: context,
                scopedWordBookID: scopedWordBookID,
                filters: filters,
                offset: offset,
                limit: limit
            )
        }

        var pageDescriptor = makeWordPageDescriptor(
            scopedWordBookID: scopedWordBookID,
            filters: filters
        )
        pageDescriptor.fetchOffset = offset
        pageDescriptor.fetchLimit = limit

        let words = try context.fetch(pageDescriptor)
        PerformanceTrace.fetch("Wordbook page fetch", count: words.count)

        let matchingCount = try context.fetchCount(
            makeWordPageDescriptor(scopedWordBookID: scopedWordBookID, filters: filters)
        )
        PerformanceTrace.fetch("Wordbook page count", count: matchingCount)

        return WordbookPage(
            rows: words.map(WordbookRowViewData.init),
            matchingCount: matchingCount,
            isMatchingCountExact: true,
            hasNextPage: offset + words.count < matchingCount
        )
    }

    func makeOptionSets(
        in context: ModelContext,
        scopedWordBookID: UUID?,
        wordBooks: [WordBook] = []
    ) throws -> WordbookOptionSets {
        var descriptor: FetchDescriptor<VocabularyWord>
        if let scopedWordBookID {
            descriptor = FetchDescriptor<VocabularyWord>(predicate: #Predicate { word in
                word.wordBook?.id == scopedWordBookID && !word.isArchived
            })
        } else {
            descriptor = FetchDescriptor<VocabularyWord>(predicate: #Predicate { word in
                !word.isArchived
            })
        }
        descriptor.propertiesToFetch = [\.jlptLevel, \.partOfSpeech, \.tags]
        descriptor.includePendingChanges = true
        let words = try context.fetch(descriptor)
        PerformanceTrace.fetch("Wordbook option set fetch", count: words.count)

        return PerformanceTrace.measure("Wordbook option set summary") {
            makeOptionSets(from: words, wordBooks: wordBooks)
        }
    }

    func filter(
        _ words: [VocabularyWord],
        using filters: WordbookFilters,
        currentWordBookID: UUID?
    ) -> [VocabularyWord] {
        let searchText = filters.searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return words.filter {
            matches($0, using: filters, currentWordBookID: currentWordBookID, searchText: searchText)
        }
    }

    func filterResult(
        _ words: [VocabularyWord],
        using filters: WordbookFilters,
        currentWordBookID: UUID?,
        visibleLimit: Int,
        selectedWordID: UUID?
    ) -> WordbookFilterResult {
        let searchText = filters.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let visibleLimit = max(0, visibleLimit)
        var visibleWords: [VocabularyWord] = []
        var matchingCount = 0
        var selectedWordMatches = selectedWordID == nil

        visibleWords.reserveCapacity(min(words.count, visibleLimit))

        for word in words where matches(word, using: filters, currentWordBookID: currentWordBookID, searchText: searchText) {
            matchingCount += 1

            if word.id == selectedWordID {
                selectedWordMatches = true
            }

            if visibleWords.count < visibleLimit {
                visibleWords.append(word)
            }
        }

        return WordbookFilterResult(
            visibleWords: visibleWords,
            matchingCount: matchingCount,
            selectedWordMatches: selectedWordMatches
        )
    }

    func makeOptionSets(from words: [VocabularyWord], wordBooks: [WordBook] = []) -> WordbookOptionSets {
        let jlptLevels = sortedUnique(words.map(\.jlptLevel))
        let partsOfSpeech = sortedUnique(words.flatMap { partOfSpeechTokenizer.tokens(from: $0.partOfSpeech) })
        let tags = sortedUnique(words.flatMap(\.tags))

        return WordbookOptionSets(
            wordBooks: wordBooks.map { WordBookOption(id: $0.id, name: $0.name) },
            jlptLevels: jlptLevels,
            partsOfSpeech: partsOfSpeech,
            tags: tags,
            learningStates: LearningState.allCases
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
        try ensureNoDuplicate(
            expression: sanitizedDraft.expression,
            reading: sanitizedDraft.reading,
            wordBookID: wordBook.id,
            excluding: nil,
            in: context
        )
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
            try ensureNoDuplicate(
                expression: sanitizedDraft.expression,
                reading: sanitizedDraft.reading,
                wordBookID: word.wordBook?.id,
                excluding: word.id,
                in: context
            )
            let oldIdentity = VocabularyWordImportKey(expression: word.japanese, reading: word.kana)
            let newIdentity = VocabularyWordImportKey(
                expression: sanitizedDraft.expression,
                reading: sanitizedDraft.reading
            )
            word.japanese = sanitizedDraft.expression
            word.kana = sanitizedDraft.reading
            word.chineseMeaning = sanitizedDraft.meaningChinese
            word.partOfSpeech = partOfSpeechTokenizer.normalized(sanitizedDraft.partOfSpeech)
            word.exampleJapanese = sanitizedDraft.exampleJapanese
            word.exampleChinese = sanitizedDraft.exampleChinese
            word.jlptLevel = sanitizedDraft.jlptLevel
            word.tags = parseTags(sanitizedDraft.tagsText)
            word.isFavorite = sanitizedDraft.isFavorite
            if oldIdentity != newIdentity {
                word.loanwordSourceTerm = nil
                word.loanwordSourceLanguageCode = nil
                word.loanwordIsWasei = false
                word.loanwordIsPartial = false
            }
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

    private func ensureNoDuplicate(
        expression: String,
        reading: String,
        wordBookID: UUID?,
        excluding currentWordID: UUID?,
        in context: ModelContext
    ) throws {
        guard let wordBookID else { return }
        let descriptor = FetchDescriptor<VocabularyWord>(predicate: #Predicate { word in
            word.wordBook?.id == wordBookID && !word.isArchived
        })
        let requestedKey = VocabularyWordImportKey(expression: expression, reading: reading)
        let hasDuplicate = try context.fetch(descriptor).contains { word in
            word.id != currentWordID
                && VocabularyWordImportKey(expression: word.japanese, reading: word.kana) == requestedKey
        }
        if hasDuplicate { throw WordbookValidationError.duplicateWord }
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

    private func matches(
        _ word: VocabularyWord,
        using filters: WordbookFilters,
        currentWordBookID: UUID?,
        searchText: String
    ) -> Bool {
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

    private func fetchPostFilteredWordPage(
        in context: ModelContext,
        scopedWordBookID: UUID?,
        filters: WordbookFilters,
        offset: Int,
        limit: Int
    ) throws -> WordbookPage {
        // Post-filtering still preserves the exact ordering and matching semantics,
        // but larger batches avoid one SwiftData round trip per visible page while
        // keeping peak materialization bounded for large stores.
        // Keep the common first-page query lean, while amortizing SwiftData
        // round trips for deeper pages that require post-fetch filtering.
        let batchSize = offset == 0 ? max(limit, 50) : max(limit, 500)
        var candidateOffset = 0
        var matchingCount = 0
        var rows: [WordbookRowViewData] = []
        rows.reserveCapacity(limit)
        var hasNextPage = false
        var exhaustedCandidates = false

        candidateScan: while true {
            var descriptor = makeWordPageDescriptor(
                scopedWordBookID: scopedWordBookID,
                filters: filters
            )
            descriptor.fetchOffset = candidateOffset
            descriptor.fetchLimit = batchSize

            let candidates = try context.fetch(descriptor)
            PerformanceTrace.fetch("Wordbook post-filter candidate fetch", count: candidates.count)
            guard !candidates.isEmpty else {
                exhaustedCandidates = true
                break
            }

            let filterStart = ContinuousClock.now
            for word in candidates where matchesPostFetchFilters(word, using: filters) {
                if matchingCount >= offset, rows.count < limit {
                    rows.append(WordbookRowViewData(word: word))
                }
                matchingCount += 1

                if matchingCount > offset + limit {
                    hasNextPage = true
                    PerformanceTrace.record(
                        "Wordbook post-fetch filter",
                        elapsed: filterStart.duration(to: .now)
                    )
                    break candidateScan
                }
            }
            PerformanceTrace.record(
                "Wordbook post-fetch filter",
                elapsed: filterStart.duration(to: .now)
            )

            candidateOffset += candidates.count
            if candidates.count < batchSize {
                exhaustedCandidates = true
                break
            }
        }

        return WordbookPage(
            rows: rows,
            matchingCount: matchingCount,
            isMatchingCountExact: exhaustedCandidates,
            hasNextPage: hasNextPage
        )
    }

    private func makeWordPageDescriptor(
        scopedWordBookID: UUID?,
        filters: WordbookFilters
    ) -> FetchDescriptor<VocabularyWord> {
        let jlptLevel = filters.jlptLevel
        let hasJLPTLevel = jlptLevel != WordbookFilterValue.all.rawValue
        let favoritesOnly = filters.favoritesOnly
        let sortBy = [
            SortDescriptor(\VocabularyWord.japanese, order: .forward),
            SortDescriptor(\VocabularyWord.kana, order: .forward)
        ]

        var descriptor: FetchDescriptor<VocabularyWord>
        if let scopedWordBookID {
            switch (hasJLPTLevel, favoritesOnly) {
            case (true, true):
                descriptor = FetchDescriptor<VocabularyWord>(
                    predicate: #Predicate { word in
                        word.wordBook?.id == scopedWordBookID
                            && !word.isArchived
                            && word.jlptLevel == jlptLevel
                            && word.isFavorite
                    },
                    sortBy: sortBy
                )
            case (true, false):
                descriptor = FetchDescriptor<VocabularyWord>(
                    predicate: #Predicate { word in
                        word.wordBook?.id == scopedWordBookID
                            && !word.isArchived
                            && word.jlptLevel == jlptLevel
                    },
                    sortBy: sortBy
                )
            case (false, true):
                descriptor = FetchDescriptor<VocabularyWord>(
                    predicate: #Predicate { word in
                        word.wordBook?.id == scopedWordBookID
                            && !word.isArchived
                            && word.isFavorite
                    },
                    sortBy: sortBy
                )
            case (false, false):
                descriptor = FetchDescriptor<VocabularyWord>(
                    predicate: #Predicate { word in
                        word.wordBook?.id == scopedWordBookID && !word.isArchived
                    },
                    sortBy: sortBy
                )
            }
        } else {
            switch (hasJLPTLevel, favoritesOnly) {
            case (true, true):
                descriptor = FetchDescriptor<VocabularyWord>(
                    predicate: #Predicate { word in
                        !word.isArchived
                            && word.jlptLevel == jlptLevel
                            && word.isFavorite
                    },
                    sortBy: sortBy
                )
            case (true, false):
                descriptor = FetchDescriptor<VocabularyWord>(
                    predicate: #Predicate { word in
                        !word.isArchived && word.jlptLevel == jlptLevel
                    },
                    sortBy: sortBy
                )
            case (false, true):
                descriptor = FetchDescriptor<VocabularyWord>(
                    predicate: #Predicate { word in
                        !word.isArchived && word.isFavorite
                    },
                    sortBy: sortBy
                )
            case (false, false):
                descriptor = FetchDescriptor<VocabularyWord>(
                    predicate: #Predicate { word in
                        !word.isArchived
                    },
                    sortBy: sortBy
                )
            }
        }
        descriptor.includePendingChanges = true
        return descriptor
    }

    private func needsPostFetchFilter(_ filters: WordbookFilters) -> Bool {
        !filters.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || filters.tag != WordbookFilterValue.all.rawValue
            || filters.learningState != WordbookFilterValue.all.rawValue
            || filters.partOfSpeech != WordbookFilterValue.all.rawValue
    }

    private func matchesPostFetchFilters(_ word: VocabularyWord, using filters: WordbookFilters) -> Bool {
        let searchText = filters.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !searchText.isEmpty {
            let matchesSearch = word.japanese.localizedCaseInsensitiveContains(searchText)
                || word.kana.localizedCaseInsensitiveContains(searchText)
                || word.chineseMeaning.localizedCaseInsensitiveContains(searchText)
            if !matchesSearch {
                return false
            }
        }

        if filters.partOfSpeech != WordbookFilterValue.all.rawValue,
           !partOfSpeechTokenizer.containsToken(filters.partOfSpeech, in: word.partOfSpeech) {
            return false
        }

        if filters.tag != WordbookFilterValue.all.rawValue,
           !word.tags.contains(filters.tag) {
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

enum WordBookValidationError: LocalizedError, Equatable {
    case missingName
    case builtInWordBookCannotBeModified
    case builtInWordBookCannotBeDeleted

    var errorDescription: String? {
        switch self {
        case .missingName:
            return "词书名称必填。"
        case .builtInWordBookCannotBeModified:
            return "内置词书不能重命名。"
        case .builtInWordBookCannotBeDeleted:
            return "内置词书不能删除。"
        }
    }
}

@MainActor
struct WordBookService {
    static let migratedDefaultBookName = "默认词书"
    private static let builtInDisplayOrder = [
        "JLPT N5",
        "JLPT N4",
        "JLPT N3",
        "JLPT N2",
        "JLPT N1"
    ]

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
        let books = try context.fetch(descriptor).sorted(by: compareWordBooksForDisplay)
        PerformanceTrace.fetch("WordBookService wordbook fetch", count: books.count)
        return books
    }

    func basicSummaries(
        for books: [WordBook],
        selectedIDString: String?
    ) -> [WordBookSummary] {
        let selectedID = selectedIDString.flatMap(UUID.init(uuidString:))
        return books.map { book in
            summary(for: book, selectedID: selectedID, counts: WordBookSummaryCounts())
        }
    }

    func fetchPreviewWords(
        in context: ModelContext,
        wordBookID: UUID,
        limit: Int
    ) throws -> [VocabularyWord] {
        var descriptor = FetchDescriptor<VocabularyWord>(
            predicate: #Predicate { word in
                word.wordBook?.id == wordBookID && !word.isArchived
            },
            sortBy: [
                SortDescriptor(\.japanese, order: .forward),
                SortDescriptor(\.kana, order: .forward)
            ]
        )
        descriptor.fetchLimit = max(0, limit)
        descriptor.includePendingChanges = true
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
        return try summaries(for: books, in: context, selectedIDString: selectedIDString, now: now)
    }

    func summaries(
        for books: [WordBook],
        in context: ModelContext,
        selectedIDString: String?,
        now: Date = Date()
    ) throws -> [WordBookSummary] {
        let selectedID = selectedIDString.flatMap(UUID.init(uuidString:))
        let words = try context.fetch(FetchDescriptor<VocabularyWord>(
            predicate: #Predicate { word in
                !word.isArchived
            }
        ))
        PerformanceTrace.fetch("WordBookService global summary word fetch", count: words.count)
        var countsByWordBookID: [UUID: WordBookSummaryCounts] = [:]

        for word in words {
            guard let wordBookID = word.wordBook?.id else {
                continue
            }

            countsByWordBookID[wordBookID, default: WordBookSummaryCounts()]
                .include(word, now: now)
        }

        return books.map { book in
            let counts = countsByWordBookID[book.id] ?? WordBookSummaryCounts()
            return WordBookSummary(
                id: book.id,
                name: book.name,
                bookDescription: book.bookDescription,
                totalWordCount: counts.totalWordCount,
                newWordCount: counts.newWordCount,
                learningWordCount: counts.learningWordCount,
                reviewWordCount: counts.reviewWordCount,
                dueReviewCount: counts.dueReviewCount,
                createdAt: book.createdAt,
                isSelected: selectedID == book.id
            )
        }
    }

    nonisolated func summaryCounts(
        in container: ModelContainer,
        wordBookID: UUID,
        now: Date = Date()
    ) async throws -> WordBookSummaryCounts {
        let store = WordBookSummarySnapshotStore(modelContainer: container)
        return try await store.summaryCounts(wordBookID: wordBookID, now: now)
    }

    func summary(
        for book: WordBook,
        selectedID: UUID?,
        counts: WordBookSummaryCounts
    ) -> WordBookSummary {
        WordBookSummary(
            id: book.id,
            name: book.name,
            bookDescription: book.bookDescription,
            totalWordCount: counts.totalWordCount,
            newWordCount: counts.newWordCount,
            learningWordCount: counts.learningWordCount,
            reviewWordCount: counts.reviewWordCount,
            dueReviewCount: counts.dueReviewCount,
            createdAt: book.createdAt,
            isSelected: selectedID == book.id
        )
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

            return StudyDuePolicy.isDue(progress: progress, now: now)
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
            guard !wordBook.isBuiltIn else {
                throw WordBookValidationError.builtInWordBookCannotBeModified
            }
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
            guard !wordBook.isBuiltIn else {
                throw WordBookValidationError.builtInWordBookCannotBeDeleted
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

    func relearnSummary(for wordBook: WordBook, now: Date = Date()) -> WordBookRelearnSummary {
        let activeWords = wordBook.words.filter { !$0.isArchived }
        let learnedWordCount = activeWords.filter { word in
            guard let progress = word.progress else {
                return false
            }
            return progress.state != .new
        }.count
        let dueReviewCount = activeWords.filter { word in
            guard let progress = word.progress else {
                return false
            }
            return StudyDuePolicy.isDue(progress: progress, now: now)
        }.count

        return WordBookRelearnSummary(
            name: wordBook.name,
            totalWordCount: activeWords.count,
            learnedWordCount: learnedWordCount,
            dueReviewCount: dueReviewCount
        )
    }

    func resetLearningProgress(
        for wordBook: WordBook,
        in context: ModelContext,
        now: Date = Date()
    ) throws {
        do {
            for word in wordBook.words where !word.isArchived {
                let progress: LearningProgress
                if let existingProgress = word.progress {
                    progress = existingProgress
                } else {
                    progress = LearningProgress(
                        state: .new,
                        dueAt: now,
                        createdAt: now,
                        updatedAt: now,
                        word: word
                    )
                    word.progress = progress
                }

                progress.state = .new
                progress.dueAt = now
                progress.intervalDays = 0
                progress.reviewCount = 0
                progress.lapseCount = 0
                progress.lastReviewedAt = nil
                progress.updatedAt = now
                word.updatedAt = now
            }

            wordBook.updatedAt = now
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

    private func compareWordBooksForDisplay(_ lhs: WordBook, _ rhs: WordBook) -> Bool {
        let lhsBuiltInIndex = Self.builtInDisplayOrder.firstIndex(of: lhs.name)
        let rhsBuiltInIndex = Self.builtInDisplayOrder.firstIndex(of: rhs.name)

        switch (lhs.isBuiltIn ? lhsBuiltInIndex : nil, rhs.isBuiltIn ? rhsBuiltInIndex : nil) {
        case let (.some(lhsIndex), .some(rhsIndex)):
            return lhsIndex < rhsIndex
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

@ModelActor
actor WordBookSummarySnapshotStore {
    func summaryCounts(wordBookID: UUID, now: Date) throws -> WordBookSummaryCounts {
        let words = try modelContext.fetch(FetchDescriptor<VocabularyWord>(
            predicate: #Predicate { word in
                word.wordBook?.id == wordBookID && !word.isArchived
            }
        ))
        PerformanceTrace.fetch("WordBookService async summary VocabularyWord fetch", count: words.count)

        let start = ContinuousClock.now
        var counts = WordBookSummaryCounts()
        for word in words {
            counts.include(word, now: now)
        }
        PerformanceTrace.record(
            "WordBookService async summary group",
            elapsed: start.duration(to: .now)
        )

        return counts
    }
}
