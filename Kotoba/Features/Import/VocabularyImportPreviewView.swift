//
//  VocabularyImportPreviewView.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import SwiftUI

struct VocabularyImportPreviewView: View {
    let preview: VocabularyImportPreview
    @Binding var duplicateHandling: VocabularyDuplicateHandling
    let isImporting: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

            Picker("重复处理方式", selection: $duplicateHandling) {
                ForEach(VocabularyDuplicateHandling.allCases) { handling in
                    Text(handling.title).tag(handling)
                }
            }
            .pickerStyle(.segmented)

            summaryGrid

            if preview.errors.isEmpty {
                EmptyStateView(
                    systemImage: "checkmark.circle",
                    title: "没有发现行错误",
                    message: "确认重复处理方式后即可导入。"
                )
                .frame(minHeight: 180)
            } else {
                errorsList
            }

                }
                .padding(24)
            }

            Divider()
            HStack {
                Spacer()

                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button(isImporting ? "正在导入..." : "正式导入", action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isImporting || preview.validRows == 0)
            }
            .padding(16)
            .background(.bar)
        }
        .frame(minWidth: 440, idealWidth: 720, maxWidth: 820, minHeight: 360, idealHeight: 560, maxHeight: 720)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CSV 导入预览")
                .font(.title2.weight(.semibold))

            Text(preview.fileName)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var summaryGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            GridRow {
                ImportSummaryCell(title: "总行数", value: preview.totalRows)
                ImportSummaryCell(title: "有效行数", value: preview.validRows)
                ImportSummaryCell(title: "错误行数", value: preview.errorRows)
            }

            GridRow {
                ImportSummaryCell(title: "重复数量", value: preview.duplicateCount)
                ImportSummaryCell(title: "新增数量", value: preview.newCount(for: duplicateHandling))
                ImportSummaryCell(title: "更新数量", value: preview.updateCount(for: duplicateHandling))
            }
        }
    }

    private var errorsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("行错误")
                .font(.headline)

            List(preview.errors) { error in
                VStack(alignment: .leading, spacing: 4) {
                    Text("第 \(error.lineNumber) 行")
                        .font(.callout.weight(.semibold))

                    Text(error.reason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 180)
        }
    }
}

private struct ImportSummaryCell: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value.formatted())
                .font(.title3.monospacedDigit().weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        )
    }
}

#Preview {
    VocabularyImportPreviewView(
        preview: VocabularyImportPreview(
            fileName: "sample_vocabulary.csv",
            totalRows: 3,
            rows: [
                VocabularyImportRow(
                    lineNumber: 2,
                    expression: "学生",
                    reading: "がくせい",
                    meaningChinese: "学生",
                    partOfSpeech: "名词",
                    exampleJapanese: "私は学生です。",
                    exampleChinese: "我是学生。",
                    jlptLevel: "N5",
                    tags: ["N5"],
                    isDuplicate: true
                )
            ],
            errors: [
                VocabularyImportRowError(lineNumber: 4, reason: "reading 必填")
            ]
        ),
        duplicateHandling: .constant(.skip),
        isImporting: false,
        onCancel: {},
        onConfirm: {}
    )
}
