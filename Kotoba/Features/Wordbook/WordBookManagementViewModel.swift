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

@MainActor
final class WordBookManagementViewModel: ObservableObject {
    @Published private(set) var summaries: [WordBookSummary] = []
    @Published private(set) var wordBooks: [WordBook] = []
    @Published var selectedWordBookID: UUID?
    @Published var editorMode: WordBookEditorMode?
    @Published var editorDraft = WordBookDraft()
    @Published var validationMessage: String?
    @Published var errorMessage: String?
    @Published var wordBookPendingDeletion: WordBook?
    @Published private(set) var conjugationStatsByWordBookID: [UUID: ConjugationStats] = [:]

    private let service: WordBookService
    private let conjugationStatsService: ConjugationStatsService

    init(
        service: WordBookService? = nil,
        conjugationStatsService: ConjugationStatsService? = nil
    ) {
        self.service = service ?? WordBookService()
        self.conjugationStatsService = conjugationStatsService ?? ConjugationStatsService()
    }

    var selectedWordBook: WordBook? {
        guard let selectedWordBookID else {
            return wordBooks.first
        }

        return wordBooks.first { $0.id == selectedWordBookID }
    }

    func load(context: ModelContext, selectedIDString: String) {
        do {
            try service.migrateLegacyWordsIfNeeded(in: context)
            wordBooks = try service.fetchWordBooks(in: context)
            summaries = try service.summaries(in: context, selectedIDString: selectedIDString)
            conjugationStatsByWordBookID = try makeConjugationStats(in: context)
            normalizeSelection()
            errorMessage = nil
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

            summaries = try service.summaries(in: context, selectedIDString: updatedSelectedIDString)
            conjugationStatsByWordBookID = try makeConjugationStats(in: context)
            return updatedSelectedIDString
        } catch {
            errorMessage = "删除词书失败：\(error.localizedDescription)"
        }

        return nil
    }

    func cancelDelete() {
        wordBookPendingDeletion = nil
    }

    func fillLocalConjugationsForSelectedWordBook(context: ModelContext, selectedIDString: String) {
        guard let selectedWordBook else {
            return
        }

        do {
            try conjugationStatsService.fillLocalRules(for: selectedWordBook, in: context)
            load(context: context, selectedIDString: selectedIDString)
        } catch {
            errorMessage = "补全活用缓存失败：\(error.localizedDescription)"
        }
    }

    private func normalizeSelection() {
        if let selectedWordBookID, wordBooks.contains(where: { $0.id == selectedWordBookID }) {
            return
        }

        selectedWordBookID = wordBooks.first?.id
    }

    private func makeConjugationStats(in context: ModelContext) throws -> [UUID: ConjugationStats] {
        var result: [UUID: ConjugationStats] = [:]
        for wordBook in wordBooks {
            result[wordBook.id] = try conjugationStatsService.stats(for: wordBook, in: context)
        }
        return result
    }
}
