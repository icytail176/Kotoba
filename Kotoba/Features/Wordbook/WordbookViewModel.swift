//
//  WordbookViewModel.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import Combine
import Foundation
import SwiftData

enum WordEditorMode: Identifiable {
    case add
    case edit(UUID)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let id):
            return "edit-\(id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .add:
            return "新增单词"
        case .edit:
            return "编辑单词"
        }
    }
}

@MainActor
final class WordbookViewModel: ObservableObject {
    static let pageSize = 50

    @Published private(set) var filteredWords: [WordbookRowViewData] = []
    @Published private(set) var matchingWordCount = 0
    @Published private(set) var isMatchingWordCountExact = true
    @Published private(set) var currentPage = 1
    @Published private(set) var hasNextPage = false
    @Published private(set) var isLoadingWords = false
    @Published private(set) var hasLoadedWords = false
    @Published private(set) var progressSummary = WordBookSummaryCounts()
    @Published private(set) var isLoadingProgressSummary = false
    @Published private(set) var detailRefreshToken = 0
    @Published private(set) var optionSets = WordbookOptionSets(
        wordBooks: [],
        jlptLevels: [],
        partsOfSpeech: [],
        tags: []
    )
    @Published var filters = WordbookFilters() {
        didSet {
            currentPage = 1
            if filters.wordBookID != oldValue.wordBookID {
                selectedWordID = nil
                selectedWordDetail = nil
                scheduleWordReload(debounce: false, reloadOptionSets: true)
                scheduleProgressSummaryReload()
            } else if filters.searchText != oldValue.searchText {
                scheduleWordReload(debounce: true, reloadOptionSets: false)
            } else {
                scheduleWordReload(debounce: false, reloadOptionSets: false)
            }
        }
    }
    @Published var selectedWordID: UUID?
    @Published var editorMode: WordEditorMode?
    @Published var editorDraft = WordEditorDraft()
    @Published var validationMessage: String?
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var wordPendingDeletion: VocabularyWord?
    @Published var wordPendingProgressReset: VocabularyWord?

    private let service: WordbookService
    private let wordBookService: WordBookService
    private var currentWordBook: WordBook?
    private var currentWordBookID: UUID?
    private var availableWordBooks: [WordBook] = []
    private var modelContext: ModelContext?
    private var wordLoadTask: Task<Void, Never>?
    private var optionSetLoadTask: Task<Void, Never>?
    private var progressSummaryTask: Task<Void, Never>?
    private var selectedWordDetail: VocabularyWord?
    private var optionSetsCache: [String: WordbookOptionSets] = [:]

    init(
        service: WordbookService? = nil,
        wordBookService: WordBookService? = nil
    ) {
        self.service = service ?? WordbookService()
        self.wordBookService = wordBookService ?? WordBookService()
    }

    var selectedWord: VocabularyWord? {
        selectedWordDetail
    }

    var isFiltering: Bool {
        filters != WordbookFilters()
    }

    var hasMoreMatchingWords: Bool {
        hasNextPage
    }

    var hasPreviousPage: Bool {
        currentPage > 1
    }

    var totalPageCount: Int? {
        guard isMatchingWordCountExact else {
            return nil
        }
        return matchingWordCount == 0 ? 0 : Int(ceil(Double(matchingWordCount) / Double(Self.pageSize)))
    }

    var pageDescription: String {
        if let totalPageCount {
            return "第 \(currentPage) / \(max(1, totalPageCount)) 页"
        }
        return "第 \(currentPage) 页"
    }

    func loadWords(
        context: ModelContext,
        selectedWordBookID: String = "",
        invalidatesOptionSets: Bool = false
    ) {
        do {
            try PerformanceTrace.measure("Wordbook initial load") {
                wordLoadTask?.cancel()
                if invalidatesOptionSets {
                    invalidateOptionSetCache()
                }
                modelContext = context
                let wordBooks = try wordBookService.fetchWordBooks(in: context)
                availableWordBooks = wordBooks
                currentWordBook = try wordBookService.resolveSelectedWordBook(
                    in: context,
                    selectedIDString: selectedWordBookID.isEmpty ? nil : selectedWordBookID
                )
                currentWordBookID = currentWordBook?.id
                try loadFirstPage(in: context)
                scheduleOptionSetReload(in: context)
                scheduleProgressSummaryReload()
            }
        } catch {
            errorMessage = "无法加载单词本：\(error.localizedDescription)"
        }
    }

    func beginAdd() {
        validationMessage = nil
        editorDraft = WordEditorDraft()
        editorMode = .add
    }

    func beginEditSelectedWord() {
        guard let selectedWord else {
            return
        }

        validationMessage = nil
        editorDraft = WordEditorDraft(word: selectedWord)
        editorMode = .edit(selectedWord.id)
    }

    func beginEditWord(id: UUID, context: ModelContext) {
        guard let word = try? service.fetchWord(id: id, in: context) else { return }
        selectedWordID = id
        selectedWordDetail = word
        beginEditSelectedWord()
    }

    func saveEditor(context: ModelContext) {
        do {
            let savedWord: VocabularyWord
            switch editorMode {
            case .add:
                guard let currentWordBook else {
                    errorMessage = "请先选择或创建词书。"
                    return
                }

                savedWord = try service.createWord(from: editorDraft, wordBook: currentWordBook, in: context)
                selectedWordID = savedWord.id
                selectedWordDetail = savedWord
            case .edit(let id):
                guard let word = try service.fetchWord(id: id, in: context) else {
                    return
                }

                try service.updateWord(word, from: editorDraft, in: context)
                savedWord = word
                selectedWordID = savedWord.id
                selectedWordDetail = savedWord
            case .none:
                return
            }

            editorMode = nil
            validationMessage = nil
            invalidateOptionSetCache()
            loadWords(context: context, selectedWordBookID: currentWordBook?.id.uuidString ?? "")
        } catch let validationError as WordbookValidationError {
            validationMessage = validationError.localizedDescription
        } catch {
            errorMessage = "保存单词失败：\(error.localizedDescription)"
        }
    }

    func cancelEditor() {
        editorMode = nil
        validationMessage = nil
    }

    func requestDeleteSelectedWord() {
        guard let selectedWord else {
            return
        }

        wordPendingDeletion = selectedWord
    }

    func requestDeleteWord(id: UUID, context: ModelContext) {
        guard let word = try? service.fetchWord(id: id, in: context) else { return }
        selectedWordID = id
        selectedWordDetail = word
        wordPendingDeletion = word
    }

    func confirmDelete(context: ModelContext) {
        guard let word = wordPendingDeletion else {
            return
        }

        do {
            try service.deleteWord(word, in: context)
            wordPendingDeletion = nil
            selectedWordID = nil
            selectedWordDetail = nil
            invalidateOptionSetCache()
            loadWords(context: context, selectedWordBookID: currentWordBook?.id.uuidString ?? "")
        } catch {
            errorMessage = "删除单词失败：\(error.localizedDescription)"
        }
    }

    func cancelDelete() {
        wordPendingDeletion = nil
    }

    func requestResetProgressForSelectedWord() {
        guard let selectedWord else {
            return
        }

        wordPendingProgressReset = selectedWord
    }

    func confirmResetProgress(context: ModelContext) {
        guard let word = wordPendingProgressReset else {
            return
        }

        do {
            try service.resetProgress(for: word, in: context)
            wordPendingProgressReset = nil
            selectedWordDetail = word
            detailRefreshToken += 1
            invalidateOptionSetCache()
            loadWords(context: context, selectedWordBookID: currentWordBook?.id.uuidString ?? "")
        } catch {
            wordPendingProgressReset = nil
            loadSelectedWordDetail()
            errorMessage = "重置学习进度失败：\(error.localizedDescription)"
        }
    }

    func cancelResetProgress() {
        wordPendingProgressReset = nil
    }

    func clearFilters() {
        filters = WordbookFilters()
    }

    func goToNextPage(context: ModelContext) {
        modelContext = context
        guard !isLoadingWords, hasNextPage else {
            return
        }
        loadPageNumber(currentPage + 1, in: context)
    }

    func goToPreviousPage(context: ModelContext) {
        modelContext = context
        guard !isLoadingWords, hasPreviousPage else {
            return
        }
        loadPageNumber(currentPage - 1, in: context)
    }

    func updateSelection(_ newSelection: UUID?) {
        if selectedWordID == newSelection {
            selectedWordID = nil
            selectedWordDetail = nil
        } else {
            selectedWordID = newSelection
            loadSelectedWordDetail()
        }
    }

    func clearSelection() {
        selectedWordID = nil
        selectedWordDetail = nil
    }

    func toggleFavoriteForSelectedWord(context: ModelContext) {
        guard let selectedWord else {
            return
        }

        do {
            try service.setFavorite(!selectedWord.isFavorite, for: selectedWord, in: context)
            try loadFirstPage(in: context)
        } catch {
            errorMessage = "保存收藏状态失败：\(error.localizedDescription)"
        }
    }

    private func scheduleWordReload(debounce: Bool, reloadOptionSets: Bool) {
        wordLoadTask?.cancel()
        PerformanceTrace.event(
            "Wordbook search task",
            debounce ? "debounce=true cancelPrevious=true" : "debounce=false cancelPrevious=true"
        )

        guard let modelContext else {
            return
        }

        let scheduledFilters = filters
        wordLoadTask = Task { [weak self] in
            if debounce {
                try? await Task.sleep(for: .milliseconds(280))
            }

            guard !Task.isCancelled,
                  let self,
                  self.filters == scheduledFilters else {
                PerformanceTrace.event("Wordbook search task", "cancelled=true")
                return
            }

            do {
                if reloadOptionSets {
                    self.scheduleOptionSetReload(in: modelContext)
                }
                try self.loadFirstPage(in: modelContext)
            } catch {
                self.errorMessage = "无法加载单词本：\(error.localizedDescription)"
            }
        }
    }

    private func loadFirstPage(in context: ModelContext) throws {
        PerformanceTrace.event("Wordbook page load", "start offset=0 limit=\(Self.pageSize)")
        filteredWords = []
        matchingWordCount = 0
        isMatchingWordCountExact = true
        currentPage = 1
        hasNextPage = false
        hasLoadedWords = false
        try loadPage(in: context, pageNumber: 1)
        hasLoadedWords = true
        PerformanceTrace.event("Wordbook page load", "finish rows=\(filteredWords.count) total=\(matchingWordCount)")
        PerformanceTrace.tableRender("Wordbook table", rowCount: filteredWords.count)
        normalizeSelection()
    }

    private func loadPageNumber(_ pageNumber: Int, in context: ModelContext) {
        guard pageNumber > 0 else {
            return
        }

        do {
            let offset = (pageNumber - 1) * Self.pageSize
            PerformanceTrace.event(
                "Wordbook page load",
                "start offset=\(offset) limit=\(Self.pageSize)"
            )
            try loadPage(in: context, pageNumber: pageNumber)
            PerformanceTrace.event(
                "Wordbook page load",
                "finish rows=\(filteredWords.count) total=\(matchingWordCount)"
            )
            PerformanceTrace.tableRender("Wordbook table", rowCount: filteredWords.count)
            normalizeSelection()
        } catch {
            errorMessage = "无法加载单词页：\(error.localizedDescription)"
        }
    }

    private func loadPage(in context: ModelContext, pageNumber: Int) throws {
        isLoadingWords = true
        defer {
            isLoadingWords = false
        }

        let offset = (pageNumber - 1) * Self.pageSize
        let page = try PerformanceTrace.measure("Wordbook page query") {
            try service.fetchWordPage(
                in: context,
                scopedWordBookID: scopedWordBookID,
                filters: filters,
                offset: offset,
                limit: Self.pageSize
            )
        }
        matchingWordCount = page.matchingCount
        isMatchingWordCountExact = page.isMatchingCountExact
        currentPage = pageNumber
        hasNextPage = page.hasNextPage
        filteredWords = page.rows
    }

    private func reloadOptionSets(in context: ModelContext) throws {
        let cacheKey = optionSetCacheKey
        if let cached = optionSetsCache[cacheKey] {
            optionSets = cached
            PerformanceTrace.event("Wordbook option set cache", "hit key=\(cacheKey)")
            return
        }

        let generated = try service.makeOptionSets(
            in: context,
            scopedWordBookID: scopedWordBookID,
            wordBooks: availableWordBooks
        )
        optionSetsCache[cacheKey] = generated
        optionSets = generated
        PerformanceTrace.event("Wordbook option set cache", "miss key=\(cacheKey)")
    }

    private func scheduleOptionSetReload(in context: ModelContext) {
        optionSetLoadTask?.cancel()
        let scheduledCacheKey = optionSetCacheKey

        if let cached = optionSetsCache[scheduledCacheKey] {
            optionSets = cached
            return
        }

        optionSets = WordbookOptionSets(
            wordBooks: availableWordBooks.map { WordBookOption(id: $0.id, name: $0.name) },
            jlptLevels: [],
            partsOfSpeech: [],
            tags: []
        )
        optionSetLoadTask = Task { [weak self] in
            await Task.yield()
            guard !Task.isCancelled,
                  let self,
                  self.optionSetCacheKey == scheduledCacheKey else {
                return
            }
            do {
                try self.reloadOptionSets(in: context)
            } catch {
                self.errorMessage = "无法加载筛选选项：\(error.localizedDescription)"
            }
        }
    }

    private func scheduleProgressSummaryReload() {
        progressSummaryTask?.cancel()
        guard let modelContext else { return }

        let wordBookID = scopedWordBookID
        let container = modelContext.container
        let service = wordBookService
        isLoadingProgressSummary = true
        progressSummaryTask = Task { [weak self] in
            do {
                let counts = try await service.summaryCounts(
                    in: container,
                    wordBookID: wordBookID,
                    now: Date()
                )
                guard !Task.isCancelled,
                      let self,
                      self.scopedWordBookID == wordBookID else { return }
                self.progressSummary = counts
                self.isLoadingProgressSummary = false
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.isLoadingProgressSummary = false
                self.errorMessage = "无法加载学习进度：\(error.localizedDescription)"
            }
        }
    }

    private var scopedWordBookID: UUID? {
        switch filters.wordBookID {
        case WordbookFilterValue.all.rawValue:
            return nil
        case WordbookFilters.currentWordBookValue:
            return currentWordBookID
        default:
            return UUID(uuidString: filters.wordBookID)
        }
    }

    private var optionSetCacheKey: String {
        scopedWordBookID?.uuidString ?? WordbookFilterValue.all.rawValue
    }

    private func invalidateOptionSetCache() {
        optionSetLoadTask?.cancel()
        optionSetsCache.removeAll()
    }

    private func loadSelectedWordDetail() {
        guard let selectedWordID, let modelContext else {
            selectedWordDetail = nil
            return
        }

        do {
            selectedWordDetail = try service.fetchWord(id: selectedWordID, in: modelContext)
        } catch {
            selectedWordDetail = nil
            errorMessage = "无法加载单词详情：\(error.localizedDescription)"
        }
    }

    private func normalizeSelection() {
        guard let currentSelectedWordID = selectedWordID else {
            selectedWordDetail = nil
            return
        }

        if filteredWords.contains(where: { $0.id == currentSelectedWordID }) {
            loadSelectedWordDetail()
            return
        }

        selectedWordID = nil
        selectedWordDetail = nil
    }
}
