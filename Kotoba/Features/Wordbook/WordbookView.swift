//
//  WordbookView.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

enum WordbookLayoutMode: Equatable {
    case compact
    case coreColumns
    case fullColumns
}

enum WordbookLayoutPolicy {
    static let coreColumnsWidth: CGFloat = 580
    static let fullColumnsWidth: CGFloat = 820
    static let splitDetailWidth: CGFloat = 860

    static func mode(for availableWidth: CGFloat) -> WordbookLayoutMode {
        if availableWidth < coreColumnsWidth { return .compact }
        if availableWidth < fullColumnsWidth { return .coreColumns }
        return .fullColumns
    }

    static func showsSplitDetail(for availableWidth: CGFloat) -> Bool {
        availableWidth >= splitDetailWidth
    }
}

struct WordbookView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppSettings.selectedWordBookIDKey) private var selectedWordBookID = ""
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

                WordbookProgressSummaryView(
                    counts: viewModel.progressSummary,
                    isLoading: viewModel.isLoadingProgressSummary
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 12)

                Divider()

                content
            }
        }
        .searchable(
            text: $viewModel.filters.searchText,
            placement: .toolbar,
            prompt: "搜索单词、读音、释义、词源或罗马音"
        )
        .task(id: selectedWordBookID) {
            viewModel.loadWords(context: modelContext, selectedWordBookID: selectedWordBookID)
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
                    viewModel.loadWords(
                        context: modelContext,
                        selectedWordBookID: selectedWordBookID,
                        invalidatesOptionSets: true
                    )
                }
            )
        }
        .sheet(item: $importViewModel.result) { result in
            VocabularyImportResultView(result: result) {
                if let wordBookID = result.wordBookID {
                    selectedWordBookID = wordBookID.uuidString
                }
                importViewModel.dismissResult()
                viewModel.loadWords(
                    context: modelContext,
                    selectedWordBookID: selectedWordBookID,
                    invalidatesOptionSets: true
                )
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
        .alert(
            "操作完成",
            isPresented: Binding(
                get: { viewModel.successMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.successMessage = nil
                    }
                }
            )
        ) {
            Button("好") {
                viewModel.successMessage = nil
            }
        } message: {
            Text(viewModel.successMessage ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoadingWords && !viewModel.hasLoadedWords {
            ProgressView("正在加载单词本…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.hasLoadedWords && viewModel.matchingWordCount == 0 && !viewModel.isFiltering {
            EmptyStateView(
                systemImage: "books.vertical",
                title: "单词本还是空的",
                message: "可以通过新增单词或 CSV 导入创建本地词书。"
            )
        } else if viewModel.hasLoadedWords && viewModel.filteredWords.isEmpty {
            VStack(spacing: 14) {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: emptyFilterTitle,
                    message: "当前搜索或筛选条件下没有结果。"
                )

                Button("清除筛选") {
                    viewModel.clearFilters()
                }
            }
        } else {
            GeometryReader { proxy in
                wordBrowser(availableWidth: proxy.size.width)
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
    }

    private var emptyFilterTitle: String {
        let query = viewModel.filters.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? "没有符合条件的单词" : "没有找到“\(query)”"
    }

    @ViewBuilder
    private func wordBrowser(availableWidth: CGFloat) -> some View {
        let mode = WordbookLayoutPolicy.mode(for: availableWidth)
        if let selectedWord = viewModel.selectedWord {
            if WordbookLayoutPolicy.showsSplitDetail(for: availableWidth) {
                HSplitView {
                    wordTablePanel(mode: mode)
                        .frame(minWidth: 260, idealWidth: 500, maxWidth: .infinity)

                    WordDetailView(
                        word: selectedWord,
                        onToggleFavorite: { viewModel.toggleFavoriteForSelectedWord(context: modelContext) },
                        onRequestResetProgress: { viewModel.requestResetProgressForSelectedWord() },
                        onClose: {
                            viewModel.clearSelection()
                        },
                        refreshToken: viewModel.detailRefreshToken
                    )
                    .frame(minWidth: 200, idealWidth: 300, maxWidth: 400)
                }
                .frame(minWidth: 0, maxWidth: .infinity)
            } else {
                WordDetailView(
                    word: selectedWord,
                    onToggleFavorite: { viewModel.toggleFavoriteForSelectedWord(context: modelContext) },
                    onRequestResetProgress: { viewModel.requestResetProgressForSelectedWord() },
                    onClose: { viewModel.clearSelection() },
                    refreshToken: viewModel.detailRefreshToken
                )
            }
        } else {
            wordTablePanel(mode: mode)
                .frame(minWidth: 260, idealWidth: 520, maxWidth: .infinity)
        }
    }

    private func wordTablePanel(mode: WordbookLayoutMode) -> some View {
        VStack(spacing: 0) {
            if mode == .compact {
                compactWordList
            } else {
                wordTable(mode: mode)
            }

            if viewModel.matchingWordCount > 0 {
                Divider()
                HStack {
                    Text(wordCountDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        viewModel.goToPreviousPage(context: modelContext)
                    } label: {
                        Label("上一页", systemImage: "chevron.left")
                    }
                    .disabled(!viewModel.hasPreviousPage || viewModel.isLoadingWords)

                    Text(viewModel.pageDescription)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 74)

                    Button {
                        viewModel.goToNextPage(context: modelContext)
                    } label: {
                        Label("下一页", systemImage: "chevron.right")
                    }
                    .disabled(!viewModel.hasNextPage || viewModel.isLoadingWords)
                }
                .controlSize(.small)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
    }

    private var wordCountDescription: String {
        if viewModel.isMatchingWordCountExact {
            return "共 \(viewModel.matchingWordCount) 条，本页 \(viewModel.filteredWords.count) 条"
        }
        return "本页 \(viewModel.filteredWords.count) 条"
    }

    private func wordTable(mode: WordbookLayoutMode) -> some View {
        Table(viewModel.filteredWords, selection: selectedWordBinding) {
            TableColumn("单词") { word in
                HStack(spacing: 6) {
                    Text(word.expression)
                        .fontWeight(.medium)

                    if word.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                    }
            }
            .lineLimit(1)
            .truncationMode(.tail)
        }
            .width(min: 90, ideal: 120, max: 180)

            TableColumn("假名") { word in
                Text(word.reading)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .width(min: 90, ideal: 110, max: 170)

            TableColumn("中文释义") { word in
                Text(word.meaningChinese)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .width(min: 120, ideal: 150, max: 260)

            if mode == .fullColumns {
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
                .width(min: 80, ideal: 110, max: 180)
            }

            TableColumn("状态") { word in
                Text(word.learningStateDisplayName)
                    .lineLimit(1)
            }
            .width(min: 80, ideal: 100, max: 140)
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .contextMenu(forSelectionType: WordbookRowViewData.ID.self) { selection in
            Button("编辑") {
                if let id = selection.first {
                    viewModel.beginEditWord(id: id, context: modelContext)
                }
            }

            Divider()

            Button("删除", role: .destructive) {
                if let id = selection.first {
                    viewModel.requestDeleteWord(id: id, context: modelContext)
                }
            }
        }
    }

    private var compactWordList: some View {
        List(viewModel.filteredWords, selection: selectedWordBinding) { word in
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(word.expression)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        if word.isFavorite {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                                .accessibilityLabel("已收藏")
                        }
                    }
                    Text(word.reading)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(word.meaningChinese)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Text(word.learningStateDisplayName)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }
            .padding(.vertical, 4)
            .tag(word.id)
            .accessibilityElement(children: .combine)
        }
    }

    private var selectedWordBinding: Binding<UUID?> {
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
            if let target = word.wrappedValue {
                Text("将删除“\(target.japanese)（\(target.kana)）”，并同时删除相关学习进度和复习记录。此操作不可撤销。")
            }
        }
    }

    func resetProgressConfirmation(
        word: Binding<VocabularyWord?>,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) -> some View {
        alert(
            "重置为未学习？",
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
            if let target = word.wrappedValue {
                Text("将清除“\(target.japanese)”的全部学习进度和复习历史，并重新作为未学习单词加入新词队列。收藏状态不会改变。")
            }
        }
    }
}

struct WordbookProgressSummaryView: View {
    let counts: WordBookSummaryCounts
    let isLoading: Bool

    init(counts: WordBookSummaryCounts, isLoading: Bool) {
        self.counts = counts
        self.isLoading = isLoading
    }

    init(summary: WordBookSummary, isLoading: Bool) {
        counts = WordBookSummaryCounts(
            totalWordCount: summary.totalWordCount,
            newWordCount: summary.newWordCount,
            learningWordCount: summary.learningWordCount,
            reviewWordCount: summary.reviewWordCount,
            dueReviewCount: summary.dueReviewCount,
            masteredWordCount: summary.masteredWordCount
        )
        self.isLoading = isLoading
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("学习进度")
                    .font(.headline)
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("正在加载学习进度")
                } else {
                    Text("已开始学习 \(counts.startedWordCount) / \(counts.totalWordCount)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(
                value: Double(counts.startedWordCount),
                total: Double(max(1, counts.totalWordCount))
            )
            .accessibilityLabel("已开始学习")
            .accessibilityValue("\(counts.startedWordCount) / \(counts.totalWordCount)")

            Text("未学习 \(counts.newWordCount)　复习中 \(counts.reviewingWordCount)　已熟练 \(counts.masteredWordCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

#Preview {
    WordbookView()
        .modelContainer(PreviewModelContainer.make())
        .frame(width: 700, height: 500)
}
