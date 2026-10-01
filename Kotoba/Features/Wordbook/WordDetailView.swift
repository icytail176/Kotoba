import SwiftData
import SwiftUI

struct WordDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let word: VocabularyWord?
    let onToggleFavorite: () -> Void
    let onRequestResetProgress: () -> Void
    let onClose: () -> Void
    let refreshToken: Int

    @State private var historyRows: [WordReviewHistoryPresentation.Row] = []
    @State private var historyTotalCount = 0
    @State private var showsAllHistory = false
    @State private var historyErrorMessage: String?

    private let conjugationEngine = ConjugationEngine()
    private let tokenizer = PartOfSpeechTokenizer()
    private let wordbookService = WordbookService()

    var body: some View {
        Group {
            if let word {
                let learning = WordDetailLearningPresentation.make(progress: word.progress)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(for: word)
                        Divider()
                        detailSection("学习进度") {
                            DetailRow(title: "词书", value: word.wordBook?.name ?? word.jlptLevel)
                            DetailRow(title: "学习状态", value: learning.stateName)
                            if let value = learning.intervalText { DetailRow(title: "当前间隔", value: value) }
                            if let value = learning.dueText { DetailRow(title: "下次复习", value: value) }
                            if let value = learning.reviewCountText { DetailRow(title: "正式复习次数", value: value) }
                            if let value = learning.lapseCountText { DetailRow(title: "遗忘次数", value: value) }
                            if let value = learning.lastReviewedText { DetailRow(title: "最近复习", value: value) }
                            if let value = learning.difficultReason { DetailRow(title: "易错原因", value: value) }
                            if WordDetailLearningPresentation.canResetToUnlearned(
                                progress: word.progress,
                                reviewLogCount: historyTotalCount
                            ) {
                                Divider()
                                Button("重置为未学习", role: .destructive, action: onRequestResetProgress)
                            }
                        }
                        detailSection("复习历史") {
                            reviewHistorySection
                        }
                        detailSection("词条") {
                            DetailRow(title: "词性", value: word.partOfSpeech)
                            DetailRow(title: "JLPT", value: word.jlptLevel)
                            DetailRow(title: "标签", value: word.tags.joined(separator: "、"))
                        }
                        detailSection("例句") {
                            DetailRow(title: "日语例句", value: word.exampleJapanese)
                            DetailRow(title: "中文翻译", value: word.exampleChinese)
                        }
                        localConjugationSection(for: word)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                EmptyStateView(
                    systemImage: "sidebar.right",
                    title: "未选择词条",
                    message: "选择左侧表格中的一行后，可以在这里查看和编辑详情。"
                )
            }
        }
        .frame(minWidth: 200)
        .task(id: historyLoadKey) {
            loadReviewHistory()
        }
        .onChange(of: word?.id) {
            showsAllHistory = false
            historyRows = []
            historyTotalCount = 0
            historyErrorMessage = nil
        }
    }

    private func header(for word: VocabularyWord) -> some View {
        let presentation = WordDetailLexicalPresentation.make(for: word)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(word.japanese).font(.largeTitle.weight(.semibold)).textSelection(.enabled)
                Spacer()
                Button(action: onToggleFavorite) {
                    Image(systemName: word.isFavorite ? "star.fill" : "star")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(word.isFavorite ? .yellow : .secondary)
                .help(word.isFavorite ? "取消收藏" : "收藏")
                .accessibilityLabel(word.isFavorite ? "取消收藏" : "收藏")
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help("关闭详情")
                    .accessibilityLabel("关闭详情")
            }
            Text(presentation.readingLine.isEmpty ? "未填写读音" : presentation.readingLine)
                .font(.title3)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .accessibilityLabel(presentation.readingAccessibilityLabel)
            Text(presentation.meaningLine)
                .font(.title3.weight(.medium))
                .textSelection(.enabled)
                .accessibilityLabel(presentation.meaningAccessibilityLabel)
        }
    }

    @ViewBuilder
    private func localConjugationSection(for word: VocabularyWord) -> some View {
        if let generated = conjugationEngine.generate(for: word), generated.conjugationClass != .none {
            detailSection("本地活用") {
                ConjugationFormsListView(forms: generated.forms, includesDictionary: false)
            }
        } else if hasAmbiguousConjugatablePartOfSpeech(word.partOfSpeech) {
            Label("词性信息不足，暂不显示活用。可编辑词条补充具体词性。", systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func hasAmbiguousConjugatablePartOfSpeech(_ value: String) -> Bool {
        let tokens = Set(tokenizer.tokens(from: value))
        return !tokens.isDisjoint(with: ["动词", "動詞", "形容词", "形容詞"])
    }

    @ViewBuilder
    private var reviewHistorySection: some View {
        if let historyErrorMessage {
            Label(historyErrorMessage, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if historyRows.isEmpty {
            Text("暂无复习记录")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(historyRows) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.reviewedAtText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(row.ratingText)
                            .fontWeight(.medium)
                        Text(row.transitionText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }

                if historyTotalCount > WordReviewHistoryPresentation.defaultLimit {
                    Button(showsAllHistory ? "只显示最近 10 条" : "显示全部") {
                        showsAllHistory.toggle()
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }

    private var historyLoadKey: String {
        "\(word?.id.uuidString ?? "none")-\(showsAllHistory)-\(refreshToken)"
    }

    private func loadReviewHistory() {
        guard let word else {
            historyRows = []
            historyTotalCount = 0
            historyErrorMessage = nil
            return
        }

        do {
            let result = try wordbookService.fetchReviewLogs(
                for: word.id,
                in: modelContext,
                limit: showsAllHistory ? nil : WordReviewHistoryPresentation.defaultLimit
            )
            historyRows = result.logs.map { WordReviewHistoryPresentation.makeRow(from: $0) }
            historyTotalCount = result.totalCount
            historyErrorMessage = nil
        } catch {
            historyRows = []
            historyTotalCount = 0
            historyErrorMessage = "无法加载复习历史。"
        }
    }

    private func detailSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }
}

private struct DetailRow: View {
    let title: String
    let value: String

    var body: some View {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedValue.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(trimmedValue).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    WordDetailView(
        word: SampleVocabularyWords.makeWords().first,
        onToggleFavorite: {},
        onRequestResetProgress: {},
        onClose: {},
        refreshToken: 0
    )
    .frame(width: 420, height: 640)
}
