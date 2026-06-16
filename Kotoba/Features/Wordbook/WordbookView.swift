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
    @StateObject private var viewModel = WordbookViewModel()
    @StateObject private var importViewModel = VocabularyImportViewModel()
    @State private var isFileImporterPresented = false

    var body: some View {
        PageScaffold(title: "单词本", subtitle: "管理本地保存的日语词汇。") {
            VStack(spacing: 0) {
                WordbookFilterBar(
                    filters: $viewModel.filters,
                    optionSets: viewModel.optionSets,
                    isFiltering: viewModel.isFiltering,
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
        .task {
            viewModel.loadWords(context: modelContext)
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

                importViewModel.loadPreview(from: url, context: modelContext)
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
                    viewModel.loadWords(context: modelContext)
                }
            )
        }
        .sheet(item: $importViewModel.result) { result in
            VocabularyImportResultView(result: result) {
                importViewModel.dismissResult()
                viewModel.loadWords(context: modelContext)
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
            HSplitView {
                wordTable
                    .frame(minWidth: 520, idealWidth: 680)

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
                .frame(minWidth: 320)
            }
        }
    }

    private var wordTable: some View {
        Table(viewModel.filteredWords, selection: $viewModel.selectedWordID) {
            TableColumn("单词") { word in
                HStack(spacing: 6) {
                    Text(word.japanese)
                        .fontWeight(.medium)

                    if word.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                    }
                }
            }

            TableColumn("假名") { word in
                Text(word.kana)
            }

            TableColumn("中文释义") { word in
                Text(word.chineseMeaning)
            }

            TableColumn("JLPT") { word in
                Text(word.jlptLevel.isEmpty ? "-" : word.jlptLevel)
            }
            .width(70)

            TableColumn("词性") { word in
                Text(word.partOfSpeech.isEmpty ? "-" : word.partOfSpeech)
            }

            TableColumn("状态") { word in
                Text(word.progress?.state.displayName ?? "-")
            }
            .width(90)
        }
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
