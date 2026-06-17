//
//  TodayStudyView.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import SwiftData
import SwiftUI

struct TodayStudyView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppSettings.dailyNewWordLimitKey) private var dailyNewWordLimit = AppSettings.defaultDailyNewWordLimit
    @AppStorage(AppSettings.selectedWordBookIDKey) private var selectedWordBookID = ""
    @StateObject private var viewModel = HomeDashboardViewModel()
    @State private var activeSessionMode: StudySession.Mode?
    @State private var isWordBookPickerPresented = false
    @State private var searchText = ""
    @State private var searchScope: HomeSearchScope = .currentWordBook
    @State private var searchSuggestions: [HomeSearchSuggestion] = []
    @State private var selectedSearchWord: VocabularyWord?
    @State private var searchErrorMessage: String?
    @FocusState private var isSearchFocused: Bool
    private let searchService = HomeSearchService()
    let onOpenWordBookManagement: () -> Void

    init(onOpenWordBookManagement: @escaping () -> Void = {}) {
        self.onOpenWordBookManagement = onOpenWordBookManagement
    }

    var body: some View {
        PageScaffold(title: "今日学习", subtitle: "选择当前词书，开始新词学习或到期复习。") {
            Group {
                if let activeSessionMode {
                    StudyView(
                        wordBookID: viewModel.snapshot.wordBookID,
                        mode: activeSessionMode,
                        completedTitle: activeSessionMode == .newWordsOnly ? "本词书暂无新词" : "当前暂无待复习单词",
                        completedMessage: activeSessionMode == .newWordsOnly
                            ? "这个词书中的新词已经学完，或今日新词数量已达上限。"
                            : "当前词书没有已经到期的复习词。"
                    )
                    .toolbar {
                        ToolbarItem {
                            Button {
                                self.activeSessionMode = nil
                                reloadDashboard()
                            } label: {
                                Label("返回首页", systemImage: "chevron.left")
                            }
                        }
                    }
                } else {
                    dashboard
                }
            }
        }
        .task(id: selectedWordBookID) {
            reloadDashboard()
        }
        .onChange(of: dailyNewWordLimit) {
            reloadDashboard()
        }
        .onChange(of: selectedWordBookID) {
            refreshSearchSuggestions()
        }
        .sheet(isPresented: $isWordBookPickerPresented) {
            WordBookPickerSheet(
                wordBooks: viewModel.wordBooks,
                selectedWordBookID: $selectedWordBookID,
                onManage: {
                    isWordBookPickerPresented = false
                    onOpenWordBookManagement()
                }
            )
        }
        .sheet(
            isPresented: Binding(
                get: { selectedSearchWord != nil },
                set: { isPresented in
                    if !isPresented {
                        selectedSearchWord = nil
                    }
                }
            )
        ) {
            if let selectedSearchWord {
                HomeSearchWordDetailView(word: selectedSearchWord)
            }
        }
        .alert(
            "首页加载失败",
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
            "搜索失败",
            isPresented: Binding(
                get: { searchErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        searchErrorMessage = nil
                    }
                }
            )
        ) {
            Button("好") {
                searchErrorMessage = nil
            }
        } message: {
            Text(searchErrorMessage ?? "")
        }
    }

    @ViewBuilder
    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if viewModel.snapshot.wordBookID == nil {
                    noWordBookState
                } else {
                    currentWordBookHeader
                    searchSection
                    randomExampleSection
                    entrySection
                    todayStatsSection
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var noWordBookState: some View {
        EmptyStateView(
            systemImage: "books.vertical",
            title: "还没有词书",
            message: "请先导入一个 CSV 词书开始学习。"
        )
        .overlay(alignment: .bottom) {
            Button {
                onOpenWordBookManagement()
            } label: {
                Label("导入词书", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("导入词书")
            .padding(.top, 140)
        }
    }

    private var currentWordBookHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("当前词书")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(viewModel.snapshot.wordBookName)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if !viewModel.snapshot.wordBookDescription.isEmpty {
                    Text(viewModel.snapshot.wordBookDescription)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 12)

            Button {
                isWordBookPickerPresented = true
            } label: {
                Label("切换词书", systemImage: "arrow.left.arrow.right")
            }
            .accessibilityLabel("切换词书")
        }
    }

    private var randomExampleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("今日一句")
                    .font(.headline)

                Spacer()

                Button {
                    viewModel.refreshExample(context: modelContext)
                } label: {
                    Label("换一句", systemImage: "shuffle")
                }
                .accessibilityLabel("换一句")
            }

            if let example = viewModel.snapshot.example {
                VStack(alignment: .leading, spacing: 8) {
                    HighlightedExampleText(example: example)
                        .font(.title3)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(example.chinese)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("当前词书暂无可展示的例句")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("搜索单词、假名、中文释义、标签或词性", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onSubmit {
                        openFirstSearchSuggestion()
                    }

                if !searchText.isEmpty {
                    Button {
                        clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("清空搜索")
                }

                Picker("搜索范围", selection: $searchScope) {
                    ForEach(HomeSearchScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.quaternary)
            }
            .onChange(of: searchText) {
                refreshSearchSuggestions()
            }
            .onChange(of: searchScope) {
                refreshSearchSuggestions()
            }
            .onExitCommand {
                if isSearchFocused || !searchText.isEmpty {
                    clearSearch()
                }
            }

            if !searchSuggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(searchSuggestions) { suggestion in
                        Button {
                            openSearchSuggestion(suggestion)
                        } label: {
                            HomeSearchSuggestionRow(suggestion: suggestion)
                        }
                        .buttonStyle(.plain)

                        if suggestion.id != searchSuggestions.last?.id {
                            Divider()
                        }
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.quaternary)
                }
            }
        }
    }

    private var entrySection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                learningButton
                reviewButton
            }

            VStack(spacing: 12) {
                learningButton
                reviewButton
            }
        }
    }

    private var learningButton: some View {
        Button {
            guard viewModel.canStartLearning else {
                return
            }

            activeSessionMode = .newWordsOnly
        } label: {
            Label("学习新词", systemImage: "sparkle.magnifyingglass")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcutIf(!isSearchFocused, "l", modifiers: [])
        .disabled(!viewModel.canStartLearning)
        .help(viewModel.canStartLearning ? "学习当前词书的新词" : "本词书暂无新词")
        .accessibilityLabel("学习新词")
    }

    private var reviewButton: some View {
        Button {
            guard viewModel.canStartReview else {
                return
            }

            activeSessionMode = .dueReviewsOnly
        } label: {
            Label("复习旧词", systemImage: "clock.arrow.circlepath")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .keyboardShortcutIf(!isSearchFocused, "r", modifiers: [])
        .disabled(!viewModel.canStartReview)
        .help(viewModel.canStartReview ? "复习当前词书中已经到期的单词" : "当前暂无待复习单词")
        .accessibilityLabel("复习旧词")
    }

    private var todayStatsSection: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
            HomeMetricView(title: "今日可学习", value: "\(viewModel.snapshot.availableNewWordCount)")
            HomeMetricView(title: "当前待复习", value: "\(viewModel.snapshot.dueReviewCount)")
            HomeMetricView(title: "词书总词数", value: "\(viewModel.snapshot.totalWordCount)")
            HomeMetricView(title: "已进入复习", value: "\(viewModel.snapshot.masteredWordCount)")
        }
    }

    private func reloadDashboard() {
        viewModel.load(
            context: modelContext,
            selectedWordBookID: selectedWordBookID,
            dailyNewWordLimit: dailyNewWordLimit
        ) { resolvedID in
            selectedWordBookID = resolvedID
        }
        refreshSearchSuggestions()
    }

    private func refreshSearchSuggestions() {
        do {
            searchSuggestions = try searchService.suggestions(
                in: modelContext,
                query: searchText,
                scope: searchScope,
                currentWordBookID: viewModel.snapshot.wordBookID
            )
            searchErrorMessage = nil
        } catch {
            searchSuggestions = []
            searchErrorMessage = "搜索本地词库失败：\(error.localizedDescription)"
        }
    }

    private func openFirstSearchSuggestion() {
        guard let firstSuggestion = searchSuggestions.first else {
            return
        }

        openSearchSuggestion(firstSuggestion)
    }

    private func openSearchSuggestion(_ suggestion: HomeSearchSuggestion) {
        do {
            selectedSearchWord = try searchService.fetchWord(id: suggestion.wordID, in: modelContext)
            searchErrorMessage = nil
        } catch {
            selectedSearchWord = nil
            searchErrorMessage = "读取单词详情失败：\(error.localizedDescription)"
        }
    }

    private func clearSearch() {
        searchText = ""
        searchSuggestions = []
        selectedSearchWord = nil
        searchErrorMessage = nil
        isSearchFocused = false
    }
}

private struct HomeSearchSuggestionRow: View {
    let suggestion: HomeSearchSuggestion

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.expression)
                    .font(.headline)
                    .lineLimit(1)

                Text(suggestion.reading)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 120, alignment: .leading)

            Text(suggestion.meaningChinese)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 12)

            Text(suggestion.wordBookName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

private struct HomeSearchWordDetailView: View {
    let word: VocabularyWord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(word.japanese)
                        .font(.largeTitle.weight(.semibold))
                    Text(word.kana)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if word.isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .accessibilityLabel("已收藏")
                }
            }

            DetailGrid(rows: detailRows)

            if !word.exampleJapanese.isEmpty || !word.exampleChinese.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if !word.exampleJapanese.isEmpty {
                        Text(word.exampleJapanese)
                            .font(.title3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !word.exampleChinese.isEmpty {
                        Text(word.exampleChinese)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("关闭") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 520, height: 520)
    }

    private var detailRows: [(String, String)] {
        var rows: [(String, String)] = [
            ("中文释义", word.chineseMeaning),
            ("词性", word.partOfSpeech),
            ("JLPT", word.jlptLevel),
            ("词书", word.wordBook?.name ?? "未归属词书"),
            ("学习状态", word.progress?.state.displayName ?? LearningState.new.displayName)
        ]

        if let dueAt = word.progress?.dueAt {
            rows.append(("下次复习", dueAt.formatted(date: .abbreviated, time: .shortened)))
        }

        if !word.tags.isEmpty {
            rows.append(("标签", word.tags.joined(separator: " / ")))
        }

        return rows.filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

private struct DetailGrid: View {
    let rows: [(String, String)]

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
            ForEach(rows, id: \.0) { row in
                GridRow {
                    Text(row.0)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(row.1)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct HighlightedExampleText: View {
    let example: HomeExample
    private let highlightingService = ExampleHighlightingService()

    var body: some View {
        Text(highlightedText)
    }

    private var highlightedText: AttributedString {
        var attributedString = AttributedString()

        for segment in highlightingService.segments(in: example.japanese, target: example.expression) {
            var segmentString = AttributedString(segment.text)
            if segment.isHighlighted {
                segmentString.inlinePresentationIntent = .stronglyEmphasized
            }
            attributedString += segmentString
        }

        return attributedString
    }
}

private struct HomeMetricView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title2.monospacedDigit().weight(.semibold))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct WordBookPickerSheet: View {
    let wordBooks: [WordBook]
    @Binding var selectedWordBookID: String
    let onManage: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("切换词书")
                .font(.title3.weight(.semibold))

            List(wordBooks, id: \.id) { wordBook in
                Button {
                    selectedWordBookID = wordBook.id.uuidString
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(wordBook.name)
                                .lineLimit(1)
                            if !wordBook.bookDescription.isEmpty {
                                Text(wordBook.bookDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        if selectedWordBookID == wordBook.id.uuidString {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 220)

            HStack {
                Button("词书管理", action: onManage)

                Spacer()

                Button("关闭") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 420, height: 360)
    }
}

#Preview {
    TodayStudyView()
        .modelContainer(PreviewModelContainer.make())
        .frame(width: 760, height: 640)
}
