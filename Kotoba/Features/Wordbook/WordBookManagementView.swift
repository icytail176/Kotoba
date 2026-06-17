//
//  WordBookManagementView.swift
//  Kotoba
//
//  Created by Codex on 2026/6/17.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct WordBookManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppSettings.selectedWordBookIDKey) private var selectedWordBookID = ""
    @StateObject private var viewModel = WordBookManagementViewModel()
    @StateObject private var importViewModel = VocabularyImportViewModel()
    @State private var isFileImporterPresented = false

    var body: some View {
        PageScaffold(title: "词书管理", subtitle: "选择、导入和维护本地词书。") {
            content
        }
        .task(id: selectedWordBookID) {
            viewModel.load(context: modelContext, selectedIDString: selectedWordBookID)
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
            WordBookEditorView(
                title: mode.title,
                draft: $viewModel.editorDraft,
                validationMessage: viewModel.validationMessage,
                onCancel: {
                    viewModel.cancelEditor()
                },
                onSave: {
                    if let updatedID = viewModel.saveEditor(context: modelContext, selectedIDString: selectedWordBookID) {
                        selectedWordBookID = updatedID
                    }
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
                }
            )
        }
        .sheet(item: $importViewModel.result) { result in
            VocabularyImportResultView(result: result) {
                if let wordBookID = result.wordBookID {
                    selectedWordBookID = wordBookID.uuidString
                }
                importViewModel.dismissResult()
                viewModel.load(context: modelContext, selectedIDString: selectedWordBookID)
            }
        }
        .alert(
            "删除词书？",
            isPresented: Binding(
                get: { viewModel.wordBookPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.cancelDelete()
                    }
                }
            )
        ) {
            Button("取消", role: .cancel) {
                viewModel.cancelDelete()
            }
            Button("删除词书及其中所有词条", role: .destructive) {
                if let updatedID = viewModel.confirmDelete(context: modelContext) {
                    selectedWordBookID = updatedID
                }
            }
        } message: {
            Text("这会同时删除该词书中的所有词条、学习进度和 ReviewLog。此操作不可撤销。")
        }
        .alert(
            "词书操作失败",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil || importViewModel.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.errorMessage = nil
                        importViewModel.errorMessage = nil
                    }
                }
            )
        ) {
            Button("好") {
                viewModel.errorMessage = nil
                importViewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? importViewModel.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.summaries.isEmpty {
            VStack(spacing: 16) {
                EmptyStateView(
                    systemImage: "books.vertical",
                    title: "还没有词书",
                    message: "导入 CSV 或新建词书后，就可以按词书学习和复习。"
                )

                HStack {
                    Button {
                        isFileImporterPresented = true
                    } label: {
                        Label("导入 CSV", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        viewModel.beginAdd()
                    } label: {
                        Label("新建词书", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HSplitView {
                wordBookList
                    .frame(minWidth: 280, idealWidth: 360, maxWidth: 460)

                wordBookDetail
                    .frame(minWidth: 300, maxWidth: .infinity)
            }
            .frame(minWidth: 0, maxWidth: .infinity)
        }
    }

    private var wordBookList: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    isFileImporterPresented = true
                } label: {
                    Label("导入 CSV", systemImage: "square.and.arrow.down")
                }

                Button {
                    viewModel.beginAdd()
                } label: {
                    Label("新建词书", systemImage: "plus")
                }

                Spacer()
            }
            .padding(12)

            Divider()

            List(selection: $viewModel.selectedWordBookID) {
                ForEach(viewModel.summaries) { summary in
                    WordBookSummaryRow(summary: summary)
                        .tag(summary.id)
                }
            }
        }
    }

    @ViewBuilder
    private var wordBookDetail: some View {
        if let wordBook = viewModel.selectedWordBook,
           let summary = viewModel.summaries.first(where: { $0.id == wordBook.id }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(wordBook.name)
                                .font(.title2.weight(.semibold))
                                .lineLimit(2)

                            if !wordBook.bookDescription.isEmpty {
                                Text(wordBook.bookDescription)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Spacer()

                        if selectedWordBookID == wordBook.id.uuidString {
                            Label("当前", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                        }
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                        BookMetricView(title: "总词数", value: summary.totalWordCount)
                        BookMetricView(title: "新词", value: summary.newWordCount)
                        BookMetricView(title: "学习中", value: summary.learningWordCount)
                        BookMetricView(title: "复习中", value: summary.reviewWordCount)
                        BookMetricView(title: "当前到期", value: summary.dueReviewCount)
                    }

                    if let conjugationStats = viewModel.conjugationStatsByWordBookID[wordBook.id] {
                        conjugationStatsSection(conjugationStats)
                    }

                    HStack {
                        Button {
                            selectedWordBookID = wordBook.id.uuidString
                            viewModel.load(context: modelContext, selectedIDString: selectedWordBookID)
                        } label: {
                            Label("选择此词书", systemImage: "checkmark")
                        }
                        .disabled(selectedWordBookID == wordBook.id.uuidString)

                        Button {
                            viewModel.beginEditSelectedWordBook()
                        } label: {
                            Label("重命名", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            viewModel.requestDeleteSelectedWordBook()
                        } label: {
                            Label("删除词书", systemImage: "trash")
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            EmptyStateView(
                systemImage: "sidebar.right",
                title: "未选择词书",
                message: "选择左侧列表中的词书后，可以查看详情和管理操作。"
            )
        }
    }

    private func conjugationStatsSection(_ stats: ConjugationStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("活用数据")
                    .font(.headline)

                Spacer()

                Button {
                    viewModel.fillLocalConjugationsForSelectedWordBook(
                        context: modelContext,
                        selectedIDString: selectedWordBookID
                    )
                } label: {
                    Label("补全缺失活用", systemImage: "wand.and.stars")
                }
                .disabled(stats.pendingCount == 0)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                BookMetricView(title: "可能需要", value: stats.possibleCount)
                BookMetricView(title: "有效", value: stats.validCount)
                BookMetricView(title: "本地规则", value: stats.localRuleCount)
                BookMetricView(title: "待补全", value: stats.pendingCount)
                BookMetricView(title: "需要检查", value: stats.needsReviewCount)
                BookMetricView(title: "失败", value: stats.invalidCount)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
    }

    private static var allowedCSVContentTypes: [UTType] {
        var types: [UTType] = [.commaSeparatedText, .plainText]
        if let csvType = UTType(filenameExtension: "csv"), !types.contains(csvType) {
            types.append(csvType)
        }

        return types
    }
}

private struct WordBookSummaryRow: View {
    let summary: WordBookSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(summary.name)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if summary.isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }

            if !summary.bookDescription.isEmpty {
                Text(summary.bookDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text("总词数 \(summary.totalWordCount) · 新词 \(summary.newWordCount) · 到期 \(summary.dueReviewCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}

private struct BookMetricView: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value.formatted())
                .font(.title3.monospacedDigit().weight(.semibold))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct WordBookEditorView: View {
    let title: String
    @Binding var draft: WordBookDraft
    let validationMessage: String?
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                TextField("词书名称", text: $draft.name)
                    .textFieldStyle(.roundedBorder)

                TextField("词书说明（可选）", text: $draft.bookDescription, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...5)
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()

                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button("保存", action: onSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

#Preview {
    WordBookManagementView()
        .modelContainer(PreviewModelContainer.make())
        .frame(width: 860, height: 620)
}
