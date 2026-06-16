//
//  WordDetailView.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import SwiftUI

struct WordDetailView: View {
    let word: VocabularyWord?
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onResetProgress: () -> Void

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
                            DetailRow(title: "下次复习", value: word.progress?.dueAt.formatted(date: .abbreviated, time: .shortened) ?? "未安排")
                        }

                        detailSection("释义") {
                            DetailRow(title: "中文释义", value: word.chineseMeaning)
                            DetailRow(title: "词性", value: word.partOfSpeech)
                            DetailRow(title: "JLPT", value: word.jlptLevel)
                            DetailRow(title: "标签", value: word.tags.joined(separator: "、"))
                        }

                        detailSection("例句") {
                            DetailRow(title: "日语例句", value: word.exampleJapanese)
                            DetailRow(title: "中文翻译", value: word.exampleChinese)
                        }

                        Spacer(minLength: 0)
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
        .frame(minWidth: 300)
    }

    private func header(for word: VocabularyWord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(word.japanese)
                    .font(.largeTitle.weight(.semibold))
                    .textSelection(.enabled)

                if word.isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                }

                Spacer()
            }

            Text(word.kana)
                .font(.title3)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack {
                Button {
                    onEdit()
                } label: {
                    Label("编辑", systemImage: "pencil")
                }

                Button {
                    onResetProgress()
                } label: {
                    Label("重置进度", systemImage: "arrow.counterclockwise")
                }

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private func detailSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

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
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(trimmedValue)
                    .font(.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension LearningState {
    var displayName: String {
        switch self {
        case .new:
            return "新词"
        case .learning:
            return "学习中"
        case .review:
            return "复习中"
        case .relearning:
            return "重新学习"
        case .suspended:
            return "已暂停"
        }
    }
}

#Preview {
    WordDetailView(
        word: SampleVocabularyWords.makeWords().first,
        onEdit: {},
        onDelete: {},
        onResetProgress: {}
    )
    .frame(width: 420, height: 640)
}
