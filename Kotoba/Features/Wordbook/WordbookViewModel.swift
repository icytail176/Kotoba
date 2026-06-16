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
    @Published private(set) var words: [VocabularyWord] = []
    @Published private(set) var filteredWords: [VocabularyWord] = []
    @Published private(set) var optionSets = WordbookOptionSets(
        jlptLevels: [],
        partsOfSpeech: [],
        tags: [],
        learningStates: []
    )
    @Published var filters = WordbookFilters() {
        didSet {
            applyFilters()
        }
    }
    @Published var selectedWordID: UUID?
    @Published var editorMode: WordEditorMode?
    @Published var editorDraft = WordEditorDraft()
    @Published var validationMessage: String?
    @Published var errorMessage: String?
    @Published var wordPendingDeletion: VocabularyWord?
    @Published var wordPendingProgressReset: VocabularyWord?

    private let service: WordbookService

    init(service: WordbookService? = nil) {
        self.service = service ?? WordbookService()
    }

    var selectedWord: VocabularyWord? {
        guard let selectedWordID else {
            return filteredWords.first
        }

        return words.first { $0.id == selectedWordID }
    }

    var isFiltering: Bool {
        filters != WordbookFilters()
    }

    func loadWords(context: ModelContext) {
        do {
            words = try service.fetchWords(in: context)
            optionSets = service.makeOptionSets(from: words)
            applyFilters()
            normalizeSelection()
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

    func saveEditor(context: ModelContext) {
        do {
            switch editorMode {
            case .add:
                let word = try service.createWord(from: editorDraft, in: context)
                selectedWordID = word.id
            case .edit(let id):
                guard let word = words.first(where: { $0.id == id }) else {
                    return
                }

                try service.updateWord(word, from: editorDraft, in: context)
                selectedWordID = word.id
            case .none:
                return
            }

            editorMode = nil
            validationMessage = nil
            loadWords(context: context)
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

    func confirmDelete(context: ModelContext) {
        guard let word = wordPendingDeletion else {
            return
        }

        do {
            try service.deleteWord(word, in: context)
            wordPendingDeletion = nil
            selectedWordID = nil
            loadWords(context: context)
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
            loadWords(context: context)
        } catch {
            errorMessage = "重置学习进度失败：\(error.localizedDescription)"
        }
    }

    func cancelResetProgress() {
        wordPendingProgressReset = nil
    }

    func clearFilters() {
        filters = WordbookFilters()
    }

    private func applyFilters() {
        filteredWords = service.filter(words, using: filters)
        normalizeSelection()
    }

    private func normalizeSelection() {
        if let selectedWordID, filteredWords.contains(where: { $0.id == selectedWordID }) {
            return
        }

        selectedWordID = filteredWords.first?.id
    }
}
