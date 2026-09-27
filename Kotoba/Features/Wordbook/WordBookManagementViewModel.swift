//
//  WordBookManagementViewModel.swift
//  Kotoba
//
//  Created by Codex on 2026/6/17.
//

import Combine
import Foundation
import SwiftData

enum WordBookEditorMode: Identifiable {
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
            return "新建词书"
        case .edit:
            return "编辑词书"
        }
    }
}

struct WordBookPreviewFilters: Equatable {
    var jlptLevel = WordbookFilterValue.all.rawValue
    var partOfSpeech = WordbookFilterValue.all.rawValue
    var learningState = WordbookFilterValue.all.rawValue
}

@MainActor
final class WordBookManagementViewModel: ObservableObject {
    private static let previewPageSize = 100

    @Published private(set) var summaries: [WordBookSummary] = []
    @Published private(set) var wordBooks: [WordBook] = []
    @Published private(set) var selectedPreviewWords: [WordbookRowViewData] = []
    @Published private(set) var selectedPreviewOptionSets = WordbookOptionSets(
        wordBooks: [],
        jlptLevels: [],
        partsOfSpeech: [],
        tags: [],
        learningStates: []
    )
    @Published private(set) var selectedPreviewMatchingCount = 0
    @Published private(set) var isLoadingSelectedPreview = false
    @Published private(set) var loadingSummaryIDs: Set<UUID> = []
    @Published var previewFilters = WordBookPreviewFilters() {
        didSet {
            reloadSelectedPreview()
        }
    }
    @Published var selectedWordBookID: UUID?
    @Published var editorMode: WordBookEditorMode?
    @Published var editorDraft = WordBookDraft()
    @Published var validationMessage: String?
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var wordBookPendingDeletion: WordBook?
    @Published private(set) var relearnSummary: WordBookRelearnSummary?
    @Published private(set) var wordBookPendingRelearn: WordBook?
    @Published var isRelearnInitialConfirmationPresented = false
    @Published var isRelearnFinalConfirmationPresented = false
    @Published var relearnConfirmationText = ""

    private let service: WordBookService
    private let wordbookService = WordbookService()
    private var modelContext: ModelContext?
    private var summaryTask: Task<Void, Never>?
    private var selectedPreviewOptionCache: [UUID: WordbookOptionSets] = [:]

    init(service: WordBookService? = nil) {
        self.service = service ?? WordBookService()
    }

    var selectedWordBook: WordBook? {
        guard let selectedWordBookID else {
            return wordBooks.first
        }

        return wordBooks.first { $0.id == selectedWordBookID }
    }

    func load(context: ModelContext, selectedIDString: String) {
        do {
            try PerformanceTrace.measure("Wordbook management load") {
                summaryTask?.cancel()
                modelContext = context
                wordBooks = try service.fetchWordBooks(in: context)
                selectedPreviewOptionCache.removeAll()
                summaries = service.basicSummaries(
                    for: wordBooks,
                    selectedIDString: selectedIDString
                )
                normalizeSelection()
                try loadSelectedPreviewFirstPage(in: context)
                startSummaryStatisticsLoad(context: context, selectedIDString: selectedIDString)
                errorMessage = nil
            }
        } catch {
            errorMessage = "无法加载词书：\(error.localizedDescription)"
        }
    }

    func beginAdd() {
        validationMessage = nil
        editorDraft = WordBookDraft()
        editorMode = .add
    }

    func beginEditSelectedWordBook() {
        guard let selectedWordBook else {
            return
        }
        guard !selectedWordBook.isBuiltIn else {
            errorMessage = "内置词书不能重命名。"
            return
        }

        validationMessage = nil
        editorDraft = WordBookDraft(wordBook: selectedWordBook)
        editorMode = .edit(selectedWordBook.id)
    }

    func saveEditor(context: ModelContext, selectedIDString: String) -> String? {
        do {
            var updatedSelectedIDString = selectedIDString
            switch editorMode {
            case .add:
                let wordBook = try service.createWordBook(from: editorDraft, in: context)
                selectedWordBookID = wordBook.id
                updatedSelectedIDString = wordBook.id.uuidString
            case .edit(let id):
                guard let wordBook = wordBooks.first(where: { $0.id == id }) else {
                    return nil
                }

                try service.updateWordBook(wordBook, from: editorDraft, in: context)
                selectedWordBookID = wordBook.id
            case .none:
                return nil
            }

            editorMode = nil
            validationMessage = nil
            load(context: context, selectedIDString: updatedSelectedIDString)
            return updatedSelectedIDString
        } catch let validationError as WordBookValidationError {
            validationMessage = validationError.localizedDescription
        } catch {
            errorMessage = "保存词书失败：\(error.localizedDescription)"
        }

        return nil
    }

    func cancelEditor() {
        editorMode = nil
        validationMessage = nil
    }

    func requestDeleteSelectedWordBook() {
        guard let selectedWordBook else {
            return
        }
        guard !selectedWordBook.isBuiltIn else {
            errorMessage = "内置词书不能删除。"
            return
        }

        wordBookPendingDeletion = selectedWordBook
    }

    func confirmDelete(context: ModelContext) -> String? {
        guard let wordBook = wordBookPendingDeletion else {
            return nil
        }

        do {
            try service.deleteWordBook(wordBook, in: context)
            wordBookPendingDeletion = nil
            wordBooks = try service.fetchWordBooks(in: context)
            let updatedSelectedIDString: String

            if let replacement = wordBooks.first {
                selectedWordBookID = replacement.id
                updatedSelectedIDString = replacement.id.uuidString
            } else {
                selectedWordBookID = nil
                updatedSelectedIDString = ""
            }

            summaries = service.basicSummaries(
                for: wordBooks,
                selectedIDString: updatedSelectedIDString
            )
            selectedPreviewOptionCache.removeAll()
            try loadSelectedPreviewFirstPage(in: context)
            startSummaryStatisticsLoad(context: context, selectedIDString: updatedSelectedIDString)
            return updatedSelectedIDString
        } catch {
            errorMessage = "删除词书失败：\(error.localizedDescription)"
        }

        return nil
    }

    func cancelDelete() {
        wordBookPendingDeletion = nil
    }

    func requestRelearnSelectedWordBook() {
        guard let selectedWordBook else {
            return
        }

        wordBookPendingRelearn = selectedWordBook
        relearnSummary = service.relearnSummary(for: selectedWordBook)
        relearnConfirmationText = ""
        isRelearnInitialConfirmationPresented = true
    }

    func continueToFinalRelearnConfirmation() {
        guard wordBookPendingRelearn != nil else {
            return
        }

        isRelearnInitialConfirmationPresented = false
        isRelearnFinalConfirmationPresented = true
    }

    var canConfirmRelearn: Bool {
        guard let wordBookPendingRelearn else {
            return false
        }

        return relearnConfirmationText.trimmingCharacters(in: .whitespacesAndNewlines) == wordBookPendingRelearn.name
    }

    func confirmRelearn(context: ModelContext, selectedIDString: String) {
        guard let wordBook = wordBookPendingRelearn, canConfirmRelearn else {
            return
        }

        do {
            try service.resetLearningProgress(for: wordBook, in: context)
            let name = wordBook.name
            cancelRelearn()
            selectedWordBookID = wordBook.id
            selectedPreviewOptionCache.removeAll()
            load(context: context, selectedIDString: selectedIDString)
            errorMessage = nil
            // The learning history intentionally remains in ReviewLog.
            successMessage = "《\(name)》已重置为新词状态，学习历史已保留。"
        } catch {
            errorMessage = "重学词书失败：\(error.localizedDescription)"
        }
    }

    func cancelRelearn() {
        isRelearnInitialConfirmationPresented = false
        isRelearnFinalConfirmationPresented = false
        relearnConfirmationText = ""
        relearnSummary = nil
        wordBookPendingRelearn = nil
    }

    func loadSelectedPreview(context: ModelContext) {
        do {
            modelContext = context
            try PerformanceTrace.measure("Wordbook management preview load") {
                try loadSelectedPreviewFirstPage(in: context)
            }
            errorMessage = nil
        } catch {
            selectedPreviewWords = []
            selectedPreviewOptionSets = WordbookOptionSets(
                wordBooks: [],
                jlptLevels: [],
                partsOfSpeech: [],
                tags: [],
                learningStates: []
            )
            selectedPreviewMatchingCount = 0
            errorMessage = "无法加载词书预览：\(error.localizedDescription)"
        }
    }

    func loadMoreSelectedPreview(context: ModelContext) {
        modelContext = context
        guard !isLoadingSelectedPreview, hasMoreSelectedPreviewWords else {
            return
        }

        do {
            try loadSelectedPreviewPage(in: context, offset: selectedPreviewWords.count, appends: true)
        } catch {
            errorMessage = "无法加载更多词条：\(error.localizedDescription)"
        }
    }

    var previewWordLimit: Int {
        Self.previewPageSize
    }

    var hasMoreSelectedPreviewWords: Bool {
        selectedPreviewMatchingCount > selectedPreviewWords.count
    }

    private func normalizeSelection() {
        if let selectedWordBookID, wordBooks.contains(where: { $0.id == selectedWordBookID }) {
            return
        }

        selectedWordBookID = wordBooks.first?.id
    }

    private func reloadSelectedPreview() {
        guard let modelContext else {
            return
        }

        do {
            try loadSelectedPreviewFirstPage(in: modelContext)
        } catch {
            errorMessage = "无法加载词书预览：\(error.localizedDescription)"
        }
    }

    private func loadSelectedPreviewFirstPage(in context: ModelContext) throws {
        selectedPreviewWords = []
        selectedPreviewMatchingCount = 0
        guard let selectedWordBookID else {
            selectedPreviewOptionSets = WordbookOptionSets(
                wordBooks: [],
                jlptLevels: [],
                partsOfSpeech: [],
                tags: [],
                learningStates: []
            )
            return
        }

        if let cachedOptionSets = selectedPreviewOptionCache[selectedWordBookID] {
            selectedPreviewOptionSets = cachedOptionSets
            PerformanceTrace.event("Wordbook management option set cache", "hit key=\(selectedWordBookID.uuidString)")
        } else {
            let optionSets = try wordbookService.makeOptionSets(
                in: context,
                scopedWordBookID: selectedWordBookID
            )
            selectedPreviewOptionCache[selectedWordBookID] = optionSets
            selectedPreviewOptionSets = optionSets
            PerformanceTrace.event("Wordbook management option set cache", "miss key=\(selectedWordBookID.uuidString)")
        }

        try loadSelectedPreviewPage(in: context, offset: 0, appends: false)
    }

    private func loadSelectedPreviewPage(in context: ModelContext, offset: Int, appends: Bool) throws {
        guard let selectedWordBookID else {
            selectedPreviewWords = []
            selectedPreviewMatchingCount = 0
            return
        }

        isLoadingSelectedPreview = true
        defer {
            isLoadingSelectedPreview = false
        }

        var filters = WordbookFilters(wordBookID: WordbookFilterValue.all.rawValue)
        filters.jlptLevel = previewFilters.jlptLevel
        filters.partOfSpeech = previewFilters.partOfSpeech
        filters.learningState = previewFilters.learningState

        let page = try PerformanceTrace.measure("Wordbook management detail page query") {
            try wordbookService.fetchWordPage(
                in: context,
                scopedWordBookID: selectedWordBookID,
                filters: filters,
                offset: offset,
                limit: Self.previewPageSize
            )
        }
        selectedPreviewMatchingCount = page.matchingCount

        if appends {
            let existingIDs = Set(selectedPreviewWords.map(\.id))
            selectedPreviewWords.append(contentsOf: page.rows.filter { !existingIDs.contains($0.id) })
        } else {
            selectedPreviewWords = page.rows
        }

        PerformanceTrace.tableRender(
            "Wordbook management detail table",
            rowCount: selectedPreviewWords.count
        )
    }

    private func startSummaryStatisticsLoad(context: ModelContext, selectedIDString: String) {
        summaryTask?.cancel()
        let wordBookIDs = wordBooks.map(\.id)
        let service = service
        let container = context.container
        let selectedID = UUID(uuidString: selectedIDString)

        loadingSummaryIDs = Set(wordBookIDs)
        summaryTask = Task { [weak self, wordBookIDs, service, container, selectedID] in
            for wordBookID in wordBookIDs {
                guard !Task.isCancelled else {
                    return
                }

                do {
                    let counts = try await service.summaryCounts(
                        in: container,
                        wordBookID: wordBookID,
                        now: Date()
                    )
                    guard !Task.isCancelled else {
                        return
                    }

                    self?.applySummaryCounts(
                        counts,
                        for: wordBookID,
                        selectedID: selectedID
                    )
                } catch {
                    self?.markSummaryFinished(for: wordBookID)
                    self?.setSummaryErrorIfNeeded(error)
                }
            }
        }
    }

    private func applySummaryCounts(_ counts: WordBookSummaryCounts, for wordBookID: UUID, selectedID: UUID?) {
        guard let index = summaries.firstIndex(where: { $0.id == wordBookID }),
              let book = wordBooks.first(where: { $0.id == wordBookID }) else {
            loadingSummaryIDs.remove(wordBookID)
            return
        }

        summaries[index] = service.summary(for: book, selectedID: selectedID, counts: counts)
        loadingSummaryIDs.remove(wordBookID)
    }

    private func markSummaryFinished(for wordBookID: UUID) {
        loadingSummaryIDs.remove(wordBookID)
    }

    private func setSummaryErrorIfNeeded(_ error: Error) {
        if errorMessage == nil {
            errorMessage = "部分词书统计加载失败：\(error.localizedDescription)"
        }
    }

}
