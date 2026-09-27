//
//  VocabularyImportResultView.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import SwiftUI
import UniformTypeIdentifiers

struct VocabularyImportResultView: View {
    @State private var isReportExporterPresented = false
    let result: VocabularyImportResult
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("导入完成")
                    .font(.title2.weight(.semibold))

                Text("已完成本次 CSV 导入，错误行已跳过。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let wordBookName = result.wordBookName {
                    Text("目标词书：\(wordBookName)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    ResultCell(title: "新增", value: result.insertedCount)
                    ResultCell(title: "更新", value: result.updatedCount)
                }

                GridRow {
                    ResultCell(title: "跳过重复", value: result.skippedDuplicateCount)
                    ResultCell(title: "忽略错误行", value: result.ignoredErrorCount)
                }
            }

            if let qualityReport = result.qualityReport {
                qualityReportSection(qualityReport)
            }

            HStack {
                Spacer()

                Button("完成", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
        .fileExporter(
            isPresented: $isReportExporterPresented,
            document: ImportQualityReportDocument(text: result.qualityReport?.makeCSVReport() ?? ""),
            contentType: .commaSeparatedText,
            defaultFilename: "kotoba_import_quality_report.csv"
        ) { _ in }
    }

    private func qualityReportSection(_ report: VocabularyImportQualityReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("导入质量报告")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    ResultCell(title: "严重错误", value: report.criticalCount)
                    ResultCell(title: "警告", value: report.warningCount)
                }

                GridRow {
                    ResultCell(title: "提示", value: report.infoCount)
                    ResultCell(title: "检查总数", value: report.issues.count)
                }
            }

            DisclosureGroup("查看质量报告") {
                qualityIssueList(report)
                    .padding(.top, 8)
            }

            Button {
                isReportExporterPresented = true
            } label: {
                Label("导出问题报告", systemImage: "square.and.arrow.up")
            }
            .disabled(!report.hasIssues)
        }
    }

    private func qualityIssueList(_ report: VocabularyImportQualityReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if report.issues.isEmpty {
                Text("未发现质量问题。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(report.issues.prefix(80)) { issue in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(issueTitle(issue))
                            .font(.callout.weight(.semibold))
                        Text(issue.reason)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                    Divider()
                }

                if report.issues.count > 80 {
                    Text("仅显示前 80 条，完整内容可导出问题报告。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxHeight: 260)
    }

    private func issueTitle(_ issue: VocabularyImportQualityIssue) -> String {
        let line = issue.lineNumber.map { "第 \($0) 行" } ?? "全局"
        let expression = issue.expression.isEmpty ? "" : " · \(issue.expression)"
        return "\(issue.severity.title)：\(line)\(expression)"
    }

}

private struct ImportQualityReportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.commaSeparatedText]
    }

    static var writableContentTypes: [UTType] {
        [.commaSeparatedText]
    }

    let text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            self.text = ""
            return
        }

        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

private struct ResultCell: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value.formatted())
                .font(.title2.monospacedDigit().weight(.semibold))
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
    VocabularyImportResultView(
        result: VocabularyImportResult(
            insertedCount: 8,
            updatedCount: 2,
            skippedDuplicateCount: 1,
            ignoredErrorCount: 3,
            wordBookID: UUID(),
            wordBookName: "N3 常用词"
        ),
        onDone: {}
    )
}
