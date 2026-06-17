//
//  WordbookView.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct WordbookView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppSettings.selectedWordBookIDKey) private var selectedWordBookID = ""
    @StateObject private var viewModel = WordbookViewModel()
    @StateObject private var importViewModel = VocabularyImportViewModel()
    @State private var isFileImporterPresented = false
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        PageScaffold(title: "单词本", subtitle: "管理本地保存的日语词汇。") {
            VStack(spacing: 0) {
                WordbookFilterBar(
                    filters: $viewModel.filters,
                    optionSets: viewModel.optionSets,
                    isFiltering: viewModel.isFiltering,
                    searchFieldFocus: $isSearchFieldFocused,
                    onClear: {
                        viewModel.clearFilters()
                    },
                    onAdd: {
                        viewModel.beginAdd()
                    },
                    onImport: {
                        isFileImporterPresented = true
                    }
                )

                Divider()

                content
            }
        }
        .task(id: selectedWordBookID) {
            viewModel.loadWords(context: modelContext, selectedWordBookID: selectedWordBookID)
        }
        .overlay(alignment: .topLeading) {
            Button("搜索") {
                isSearchFieldFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: Self.allowedCSVContentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    return
                }

                importViewModel.prepareFile(
                    from: url,
                    context: modelContext,
                    preferredWordBookID: selectedWordBookID
                )
            case .failure(let error):
                importViewModel.errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $viewModel.editorMode) { mode in
            WordEditorView(
                title: mode.title,
                draft: $viewModel.editorDraft,
                validationMessage: viewModel.validationMessage,
                onCancel: {
                    viewModel.cancelEditor()
                },
                onSave: {
                    viewModel.saveEditor(context: modelContext)
                }
            )
        }
        .sheet(isPresented: $importViewModel.isTargetConfigurationPresented) {
            VocabularyImportTargetView(
                viewModel: importViewModel,
                onCancel: {
                    importViewModel.cancelTargetSelection()
                },
                onConfirm: {
                    importViewModel.confirmTargetSelection(context: modelContext)
                }
            )
        }
        .sheet(item: $importViewModel.preview) { preview in
            VocabularyImportPreviewView(
                preview: preview,
                duplicateHandling: $importViewModel.duplicateHandling,
                isImporting: importViewModel.isImporting,
                onCancel: {
                    importViewModel.cancelPreview()
                },
                onConfirm: {
                    importViewModel.confirmImport(context: modelContext)
                    viewModel.loadWords(context: modelContext, selectedWordBookID: selectedWordBookID)
                }
            )
        }
        .sheet(item: $importViewModel.result) { result in
            VocabularyImportResultView(result: result) {
                if let wordBookID = result.wordBookID {
                    selectedWordBookID = wordBookID.uuidString
                }
                importViewModel.dismissResult()
                viewModel.loadWords(context: modelContext, selectedWordBookID: selectedWordBookID)
            }
        }
        .deleteConfirmation(
            word: $viewModel.wordPendingDeletion,
            onCancel: {
                viewModel.cancelDelete()
            },
            onConfirm: {
                viewModel.confirmDelete(context: modelContext)
            }
        )
        .resetProgressConfirmation(
            word: $viewModel.wordPendingProgressReset,
            onCancel: {
                viewModel.cancelResetProgress()
            },
            onConfirm: {
                viewModel.confirmResetProgress(context: modelContext)
            }
        )
        .alert(
            "CSV 导入失败",
            isPresented: Binding(
                get: { importViewModel.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        importViewModel.errorMessage = nil
                    }
                }
            )
        ) {
            Button("好") {
                importViewModel.errorMessage = nil
            }
        } message: {
            Text(importViewModel.errorMessage ?? "")
        }
        .alert(
            "单词本操作失败",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.errorMessage = nil
                    }
                }
            )
        ) {
            Button("好") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.words.isEmpty {
            EmptyStateView(
                systemImage: "books.vertical",
                title: "单词本还是空的",
                message: "可以通过新增单词或 CSV 导入创建本地词书。"
            )
        } else if viewModel.filteredWords.isEmpty {
            VStack(spacing: 14) {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: "没有匹配的词条",
                    message: "当前搜索或筛选条件下没有结果。"
                )

                Button("清除筛选") {
                    viewModel.clearFilters()
                }
            }
        } else {
            if viewModel.selectedWord == nil {
                wordTable
                    .frame(minWidth: 360, idealWidth: 560, maxWidth: .infinity)
            } else {
                HSplitView {
                    wordTable
                        .frame(minWidth: 360, idealWidth: 560, maxWidth: .infinity)

                    WordDetailView(
                        word: viewModel.selectedWord,
                        onEdit: {
                            viewModel.beginEditSelectedWord()
                        },
                        onDelete: {
                            viewModel.requestDeleteSelectedWord()
                        },
                        onResetProgress: {
                            viewModel.requestResetProgressForSelectedWord()
                        }
                    )
                    .frame(minWidth: 240, idealWidth: 320, maxWidth: 420)
                }
                .frame(minWidth: 0, maxWidth: .infinity)
            }
        }
    }

    private var wordTable: some View {
        Table(viewModel.filteredWords, selection: selectedWordBinding) {
            TableColumn("单词") { word in
                HStack(spacing: 6) {
                    Text(word.japanese)
                        .fontWeight(.medium)

                    if word.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                    }
                }
                .lineLimit(1)
                .truncationMode(.tail)
            }
            .width(min: 100, ideal: 140, max: 220)

            TableColumn("假名") { word in
                Text(word.kana)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .width(min: 100, ideal: 130, max: 200)

            TableColumn("中文释义") { word in
                Text(word.chineseMeaning)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .width(min: 120, ideal: 170, max: 280)

            TableColumn("JLPT") { word in
                Text(word.jlptLevel.isEmpty ? "-" : word.jlptLevel)
                    .lineLimit(1)
            }
            .width(min: 60, ideal: 70, max: 90)

            TableColumn("词性") { word in
                Text(word.partOfSpeech.isEmpty ? "-" : word.partOfSpeech)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .width(min: 90, ideal: 120, max: 180)

            TableColumn("状态") { word in
                Text(word.progress?.state.displayName ?? "-")
                    .lineLimit(1)
            }
            .width(min: 90, ideal: 110, max: 160)
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .contextMenu(forSelectionType: VocabularyWord.ID.self) { selection in
            Button("编辑") {
                if let id = selection.first {
                    viewModel.selectedWordID = id
                }
                viewModel.beginEditSelectedWord()
            }

            Button("重置学习进度") {
                if let id = selection.first {
                    viewModel.selectedWordID = id
                }
                viewModel.requestResetProgressForSelectedWord()
            }

            Divider()

            Button("删除", role: .destructive) {
                if let id = selection.first {
                    viewModel.selectedWordID = id
                }
                viewModel.requestDeleteSelectedWord()
            }
        }
    }

    private var selectedWordBinding: Binding<VocabularyWord.ID?> {
        Binding {
            viewModel.selectedWordID
        } set: { newSelection in
            viewModel.updateSelection(newSelection)
        }
    }

    private static var allowedCSVContentTypes: [UTType] {
        var contentTypes: [UTType] = [.plainText]
        if let csvType = UTType(filenameExtension: "csv") {
            contentTypes.insert(csvType, at: 0)
        }

        return contentTypes
    }
}

private extension View {
    func deleteConfirmation(
        word: Binding<VocabularyWord?>,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) -> some View {
        alert(
            "确认删除单词？",
            isPresented: Binding(
                get: { word.wrappedValue != nil },
                set: { isPresented in
                    if !isPresented {
                        onCancel()
                    }
                }
            )
        ) {
            Button("取消", role: .cancel, action: onCancel)
            Button("删除", role: .destructive, action: onConfirm)
        } message: {
            Text("删除后会同时删除相关学习进度和复习记录，此操作不可撤销。")
        }
    }

    func resetProgressConfirmation(
        word: Binding<VocabularyWord?>,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) -> some View {
        alert(
            "确认重置学习进度？",
            isPresented: Binding(
                get: { word.wrappedValue != nil },
                set: { isPresented in
                    if !isPresented {
                        onCancel()
                    }
                }
            )
        ) {
            Button("取消", role: .cancel, action: onCancel)
            Button("重置", role: .destructive, action: onConfirm)
        } message: {
            Text("该单词会回到新词状态，已有复习记录会被清空。")
        }
    }
}

#Preview {
    WordbookView()
        .modelContainer(PreviewModelContainer.make())
        .frame(width: 700, height: 500)
}
