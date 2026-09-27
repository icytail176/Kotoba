//
//  WordEditorView.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import SwiftUI

struct WordEditorView: View {
    let title: String
    @Binding var draft: WordEditorDraft
    let validationMessage: String?
    let onCancel: () -> Void
    let onSave: () -> Void
    private let previewService = WordEditorPreviewService()

    private var preview: WordEditorPreview {
        previewService.makePreview(from: draft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.title2.weight(.semibold))

            Form {
                Section("基本信息") {
                    TextField("日语单词", text: $draft.expression)
                    TextField("假名", text: $draft.reading)
                    TextField("中文释义", text: $draft.meaningChinese)
                    TextField("词性", text: $draft.partOfSpeech)

                    Picker("JLPT", selection: $draft.jlptLevel) {
                        Text("未设置").tag("")
                        Text("N5").tag("N5")
                        Text("N4").tag("N4")
                        Text("N3").tag("N3")
                        Text("N2").tag("N2")
                        Text("N1").tag("N1")
                    }
                }

                Section("例句") {
                    TextField("日语例句", text: $draft.exampleJapanese, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("中文翻译", text: $draft.exampleChinese, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("整理") {
                    TextField("标签，使用英文分号分隔", text: $draft.tagsText)
                    Toggle("收藏", isOn: $draft.isFavorite)
                }

                Section("即时预览") {
                    previewContent(preview)
                }
            }
            .formStyle(.grouped)

            if let validationMessage {
                Text(validationMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
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
        .frame(minWidth: 520, minHeight: 560)
    }

    private func previewContent(_ preview: WordEditorPreview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if preview.isConjugatable, !preview.forms.isEmpty {
                ConjugationFormsListView(
                    forms: preview.forms,
                    includesDictionary: true
                )
            }

            ForEach(preview.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    WordEditorView(
        title: "新增单词",
        draft: .constant(WordEditorDraft()),
        validationMessage: "日语单词、假名、中文释义 必填。",
        onCancel: {},
        onSave: {}
    )
}
