import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum WordBookManagementLayoutMode: Equatable {
    case split
    case stacked
}

enum WordBookManagementLayoutPolicy {
    static let minimumSplitWidth: CGFloat = 600
    static let minimumDetailWidth: CGFloat = 320
    static let minimumPartOfSpeechWidth: CGFloat = 520

    static func mode(for availableWidth: CGFloat) -> WordBookManagementLayoutMode {
        availableWidth >= minimumSplitWidth ? .split : .stacked
    }

    static func listMaximumWidth(for availableWidth: CGFloat) -> CGFloat {
        min(360, max(280, availableWidth - minimumDetailWidth))
    }

    static func detailHorizontalPadding(for availableWidth: CGFloat) -> CGFloat {
        availableWidth < 460 ? 16 : 24
    }

    static func showsPartOfSpeech(for detailWidth: CGFloat) -> Bool {
        detailWidth >= minimumPartOfSpeechWidth
    }
}

struct WordBookManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppSettings.selectedWordBookIDKey) private var selectedWordBookID = ""
    @StateObject private var viewModel = WordBookManagementViewModel()
    @StateObject private var importViewModel = VocabularyImportViewModel()
    @State private var isFileImporterPresented = false
    let onOpenWordBook: () -> Void

    init(onOpenWordBook: @escaping () -> Void = {}) {
        self.onOpenWordBook = onOpenWordBook
    }

    var body: some View {
        PageScaffold(title: "词书", subtitle: "选择 JLPT 或用户词书，并查看学习进度。") {
            content
        }
        .task(id: selectedWordBookID) {
            viewModel.load(context: modelContext, selectedIDString: selectedWordBookID)
        }
        .onChange(of: viewModel.selectedWordBookID) {
            viewModel.loadSelectedPreview(context: modelContext)
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: Self.allowedCSVContentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    importViewModel.prepareFile(from: url, context: modelContext, preferredWordBookID: selectedWordBookID)
                }
            case .failure(let error):
                importViewModel.errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $viewModel.editorMode) { mode in
            WordBookEditorView(
                title: mode.title,
                draft: $viewModel.editorDraft,
                validationMessage: viewModel.validationMessage,
                onCancel: { viewModel.cancelEditor() },
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
                onCancel: { importViewModel.cancelTargetSelection() },
                onConfirm: { importViewModel.confirmTargetSelection(context: modelContext) }
            )
        }
        .sheet(item: $importViewModel.preview) { preview in
            VocabularyImportPreviewView(
                preview: preview,
                duplicateHandling: $importViewModel.duplicateHandling,
                isImporting: importViewModel.isImporting,
                onCancel: { importViewModel.cancelPreview() },
                onConfirm: { importViewModel.confirmImport(context: modelContext) }
            )
        }
        .sheet(item: $importViewModel.result) { result in
            VocabularyImportResultView(result: result) {
                if let wordBookID = result.wordBookID { selectedWordBookID = wordBookID.uuidString }
                importViewModel.dismissResult()
                viewModel.load(context: modelContext, selectedIDString: selectedWordBookID)
            }
        }
        .alert("删除词书？", isPresented: deleteConfirmationBinding) {
            Button("取消", role: .cancel) { viewModel.cancelDelete() }
            Button("删除词书及其中所有词条", role: .destructive) {
                if let updatedID = viewModel.confirmDelete(context: modelContext) { selectedWordBookID = updatedID }
            }
        } message: {
            Text("这会同时删除该词书中的所有词条、学习进度和复习记录。此操作不可撤销。")
        }
        .alert("重学此词书？", isPresented: $viewModel.isRelearnInitialConfirmationPresented) {
            Button("取消", role: .cancel) { viewModel.cancelRelearn() }
            Button("继续确认", role: .destructive) { viewModel.continueToFinalRelearnConfirmation() }
        } message: { Text(relearnConfirmationMessage) }
        .sheet(isPresented: $viewModel.isRelearnFinalConfirmationPresented) {
            RelearnWordBookConfirmationSheet(
                wordBookName: viewModel.wordBookPendingRelearn?.name ?? "",
                confirmationText: $viewModel.relearnConfirmationText,
                canConfirm: viewModel.canConfirmRelearn,
                onCancel: { viewModel.cancelRelearn() },
                onConfirm: { viewModel.confirmRelearn(context: modelContext, selectedIDString: selectedWordBookID) }
            )
        }
        .alert("词书操作失败", isPresented: errorBinding) {
            Button("好") {
                viewModel.errorMessage = nil
                importViewModel.errorMessage = nil
            }
        } message: { Text(viewModel.errorMessage ?? importViewModel.errorMessage ?? "") }
        .alert("操作完成", isPresented: successBinding) {
            Button("好") { viewModel.successMessage = nil }
        } message: { Text(viewModel.successMessage ?? "") }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.summaries.isEmpty {
            VStack(spacing: 16) {
                EmptyStateView(systemImage: "books.vertical", title: "还没有词书", message: "导入 CSV 或新建词书后即可开始学习。")
                HStack {
                    Button("导入 CSV", systemImage: "square.and.arrow.down") { isFileImporterPresented = true }
                    Button("新建词书", systemImage: "plus") { viewModel.beginAdd() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { proxy in
                switch WordBookManagementLayoutPolicy.mode(for: proxy.size.width) {
                case .split:
                    splitContent(availableWidth: proxy.size.width)
                case .stacked:
                    stackedContent
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
    }

    private func splitContent(availableWidth: CGFloat) -> some View {
        let maximumListWidth = WordBookManagementLayoutPolicy.listMaximumWidth(for: availableWidth)

        return HSplitView {
            wordBookList
                .frame(minWidth: 280, idealWidth: min(320, maximumListWidth), maxWidth: maximumListWidth)

            wordBookDetail(isStacked: false)
                .frame(minWidth: 0, idealWidth: 480, maxWidth: .infinity)
                .layoutPriority(1)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }

    private var stackedContent: some View {
        VSplitView {
            wordBookList
                .frame(minWidth: 0, maxWidth: .infinity)
                .frame(minHeight: 130, idealHeight: 160, maxHeight: 200)

            wordBookDetail(isStacked: true)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 220, maxHeight: .infinity)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }

    private var wordBookList: some View {
        VStack(spacing: 0) {
            HStack {
                Button("导入 CSV", systemImage: "square.and.arrow.down") { isFileImporterPresented = true }
                Button("新建词书", systemImage: "plus") { viewModel.beginAdd() }
                Spacer()
            }
            .padding(12)
            Divider()
            List(selection: $viewModel.selectedWordBookID) {
                ForEach(viewModel.summaries) { summary in
                    WordBookSummaryRow(summary: summary, isLoading: viewModel.loadingSummaryIDs.contains(summary.id))
                        .tag(summary.id)
                }
            }
        }
    }

    private func wordBookDetail(isStacked: Bool) -> some View {
        GeometryReader { proxy in
            if let wordBook = viewModel.selectedWordBook,
               let summary = viewModel.summaries.first(where: { $0.id == wordBook.id }) {
                if isStacked {
                    ScrollView {
                        selectedWordBookDetail(
                            wordBook: wordBook,
                            summary: summary,
                            availableWidth: proxy.size.width,
                            fixedPreviewHeight: 240
                        )
                    }
                } else {
                    selectedWordBookDetail(
                        wordBook: wordBook,
                        summary: summary,
                        availableWidth: proxy.size.width,
                        fixedPreviewHeight: nil
                    )
                }
            } else {
                EmptyStateView(systemImage: "sidebar.right", title: "未选择词书", message: "选择左侧词书查看详情。")
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }

    private func selectedWordBookDetail(
        wordBook: WordBook,
        summary: WordBookSummary,
        availableWidth: CGFloat,
        fixedPreviewHeight: CGFloat?
    ) -> some View {
        let horizontalPadding = WordBookManagementLayoutPolicy.detailHorizontalPadding(for: availableWidth)
        let showsPartOfSpeech = WordBookManagementLayoutPolicy.showsPartOfSpeech(for: availableWidth)

        return VStack(alignment: .leading, spacing: 14) {
            wordBookHeader(wordBook)
            wordBookActions(wordBook)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 96), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                BookMetricView(title: "总词数", value: summary.totalWordCount)
                BookMetricView(title: "已学习", value: summary.learningWordCount + summary.reviewWordCount)
                BookMetricView(title: "待复习", value: summary.dueReviewCount)
            }

            Text("词条预览")
                .font(.headline)

            previewFilters

            if viewModel.selectedPreviewWords.isEmpty {
                EmptyStateView(systemImage: "text.book.closed", title: "暂无词条", message: "可通过 CSV 导入添加词条。")
                    .frame(minHeight: fixedPreviewHeight ?? 120)
            } else {
                previewTable(showsPartOfSpeech: showsPartOfSpeech)
                    .frame(
                        minWidth: 0,
                        maxWidth: .infinity,
                        minHeight: fixedPreviewHeight ?? 80,
                        idealHeight: fixedPreviewHeight,
                        maxHeight: fixedPreviewHeight ?? .infinity
                    )

                if viewModel.hasMoreSelectedPreviewWords {
                    Button("加载更多", systemImage: "arrow.down.circle") {
                        viewModel.loadMoreSelectedPreview(context: modelContext)
                    }
                }
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 18)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
    }

    private var previewFilters: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { previewFilterPickers }
            VStack(alignment: .leading, spacing: 10) { previewFilterPickers }
        }
    }

    @ViewBuilder
    private var previewFilterPickers: some View {
        Picker("状态", selection: $viewModel.previewFilters.learningState) {
            Text("全部").tag(WordbookFilterValue.all.rawValue)
            ForEach(viewModel.selectedPreviewOptionSets.learningStates) { state in
                Text(state.displayName).tag(state.rawValue)
            }
        }
        Picker("词性", selection: $viewModel.previewFilters.partOfSpeech) {
            Text("全部").tag(WordbookFilterValue.all.rawValue)
            ForEach(viewModel.selectedPreviewOptionSets.partsOfSpeech, id: \.self) { Text($0).tag($0) }
        }
        Picker("JLPT", selection: $viewModel.previewFilters.jlptLevel) {
            Text("全部").tag(WordbookFilterValue.all.rawValue)
            ForEach(viewModel.selectedPreviewOptionSets.jlptLevels, id: \.self) { Text($0).tag($0) }
        }
    }

    private func wordBookHeader(_ wordBook: WordBook) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                wordBookIdentity(wordBook)
                Spacer(minLength: 8)
                currentWordBookLabel(wordBook)
            }

            VStack(alignment: .leading, spacing: 8) {
                wordBookIdentity(wordBook)
                currentWordBookLabel(wordBook)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private func wordBookIdentity(_ wordBook: WordBook) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(wordBook.name)
                .font(.title2.weight(.semibold))
                .lineLimit(2)
                .truncationMode(.tail)

            if !wordBook.bookDescription.isEmpty {
                Text(wordBook.bookDescription)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func currentWordBookLabel(_ wordBook: WordBook) -> some View {
        if selectedWordBookID == wordBook.id.uuidString {
            Label("当前词书", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.tint)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func wordBookActions(_ wordBook: WordBook) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                setCurrentWordBookButton(wordBook)
                openWordBookButton(wordBook)
                relearnWordBookButton
                wordBookMenu(wordBook)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    setCurrentWordBookButton(wordBook)
                    openWordBookButton(wordBook)
                }
                HStack(spacing: 8) {
                    relearnWordBookButton
                    wordBookMenu(wordBook)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                setCurrentWordBookButton(wordBook)
                openWordBookButton(wordBook)
                HStack(spacing: 8) {
                    relearnWordBookButton
                    wordBookMenu(wordBook)
                }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private func setCurrentWordBookButton(_ wordBook: WordBook) -> some View {
        Button("设为当前词书", systemImage: "checkmark") {
            selectedWordBookID = wordBook.id.uuidString
        }
        .disabled(selectedWordBookID == wordBook.id.uuidString)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func openWordBookButton(_ wordBook: WordBook) -> some View {
        Button("打开词书", systemImage: "book") {
            selectedWordBookID = wordBook.id.uuidString
            onOpenWordBook()
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var relearnWordBookButton: some View {
        Button("重学此词书", systemImage: "arrow.counterclockwise", role: .destructive) {
            viewModel.requestRelearnSelectedWordBook()
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func wordBookMenu(_ wordBook: WordBook) -> some View {
        if !wordBook.isBuiltIn {
            Menu {
                Button("重命名", systemImage: "pencil") { viewModel.beginEditSelectedWordBook() }
                Button("删除词书", systemImage: "trash", role: .destructive) { viewModel.requestDeleteSelectedWordBook() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .fixedSize(horizontal: true, vertical: false)
            .help("更多词书操作")
            .accessibilityLabel("更多词书操作")
        }
    }

    private func previewTable(showsPartOfSpeech: Bool) -> some View {
        Table(viewModel.selectedPreviewWords) {
            TableColumn("单词") { word in
                Text(word.expression)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .width(min: 78, ideal: 110, max: 150)

            TableColumn("假名") { word in
                Text(word.reading)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .width(min: 78, ideal: 110, max: 150)

            TableColumn("中文释义") { word in
                Text(word.meaningChinese)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .width(min: 110, ideal: 180, max: .infinity)

            if showsPartOfSpeech {
                TableColumn("词性") { word in
                    Text(word.partOfSpeech.isEmpty ? "-" : word.partOfSpeech)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .width(min: 68, ideal: 88, max: 120)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity)
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding { viewModel.wordBookPendingDeletion != nil } set: { if !$0 { viewModel.cancelDelete() } }
    }

    private var errorBinding: Binding<Bool> {
        Binding { viewModel.errorMessage != nil || importViewModel.errorMessage != nil } set: {
            if !$0 { viewModel.errorMessage = nil; importViewModel.errorMessage = nil }
        }
    }

    private var successBinding: Binding<Bool> {
        Binding { viewModel.successMessage != nil } set: { if !$0 { viewModel.successMessage = nil } }
    }

    private var relearnConfirmationMessage: String {
        guard let summary = viewModel.relearnSummary else { return "此操作会重置学习进度。" }
        return "《\(summary.name)》共 \(summary.totalWordCount) 词，其中 \(summary.learnedWordCount) 词已有进度。复习历史会保留。"
    }

    private static var allowedCSVContentTypes: [UTType] {
        var types: [UTType] = [.plainText]
        if let csv = UTType(filenameExtension: "csv") { types.insert(csv, at: 0) }
        return types
    }
}

private struct WordBookSummaryRow: View {
    let summary: WordBookSummary
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(summary.name).fontWeight(.medium).lineLimit(1)
                if summary.isSelected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
            }
            Text(isLoading
                 ? "统计中…"
                 : "总词数 \(summary.totalWordCount) · 已学习 \(summary.learningWordCount + summary.reviewWordCount) · 待复习 \(summary.dueReviewCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}

struct BookMetricView: View {
    let title: String
    let value: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value.formatted()).font(.title3.monospacedDigit().weight(.semibold))
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
            Text(title).font(.title2.weight(.semibold))
            TextField("词书名称", text: $draft.name).textFieldStyle(.roundedBorder)
            TextField("词书说明（可选）", text: $draft.bookDescription, axis: .vertical).lineLimit(3...5)
            if let validationMessage { Text(validationMessage).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                Button("保存", action: onSave).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

private struct RelearnWordBookConfirmationSheet: View {
    let wordBookName: String
    @Binding var confirmationText: String
    let canConfirm: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("确认重学").font(.title3.weight(.semibold))
            Text("请输入词书名称“\(wordBookName)”确认。词书学习状态会恢复为新词，历史统计记录保留。")
                .foregroundStyle(.secondary)
            TextField("词书名称", text: $confirmationText).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                Button("确认重学", role: .destructive, action: onConfirm)
                    .disabled(!canConfirm)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

#Preview {
    WordBookManagementView()
        .modelContainer(PreviewModelContainer.make())
        .frame(width: 860, height: 620)
}
