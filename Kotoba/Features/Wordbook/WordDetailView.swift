import SwiftUI

struct WordDetailView: View {
    let word: VocabularyWord?
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onResetProgress: () -> Void
    let onClose: () -> Void

    private let conjugationEngine = ConjugationEngine()
    private let tokenizer = PartOfSpeechTokenizer()

    var body: some View {
        Group {
            if let word {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(for: word)
                        Divider()
                        detailSection("学习进度") {
                            DetailRow(title: "状态", value: word.progress?.state.displayName ?? "未初始化")
                            DetailRow(title: "间隔", value: "\(word.progress?.intervalDays ?? 0) 天")
                            DetailRow(title: "复习次数", value: "\(word.progress?.reviewCount ?? 0)")
                            DetailRow(title: "遗忘次数", value: "\(word.progress?.lapseCount ?? 0)")
                            DetailRow(title: "下次复习", value: word.progress.map { NextReviewDateFormatter.string(for: $0.dueAt) } ?? "未安排")
                        }
                        detailSection("词条") {
                            DetailRow(title: "中文释义", value: word.chineseMeaning)
                            DetailRow(title: "词性", value: word.partOfSpeech)
                            DetailRow(title: "JLPT", value: word.jlptLevel)
                            DetailRow(title: "标签", value: word.tags.joined(separator: "、"))
                            if let etymology = LoanwordEtymologyPresentation.make(for: word) {
                                DetailRow(title: etymology.title, value: etymology.value)
                            }
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
    }

    private func header(for word: VocabularyWord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(word.japanese).font(.largeTitle.weight(.semibold)).textSelection(.enabled)
                if word.isFavorite { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help("关闭详情")
                    .accessibilityLabel("关闭详情")
            }
            Text(word.kana.isEmpty ? "未填写读音" : word.kana)
                .font(.title3)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            ViewThatFits(in: .horizontal) {
                HStack { actionButtons }
                VStack(alignment: .leading, spacing: 8) { actionButtons }
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button(action: onEdit) { Label("编辑", systemImage: "pencil") }
        Button(action: onResetProgress) {
            Label(
                word?.progress?.state == .suspended ? "重新加入学习" : "重置学习记录",
                systemImage: "arrow.counterclockwise"
            )
        }
        Button(role: .destructive, action: onDelete) { Label("删除", systemImage: "trash") }
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
        onEdit: {},
        onDelete: {},
        onResetProgress: {},
        onClose: {}
    )
    .frame(width: 420, height: 640)
}
