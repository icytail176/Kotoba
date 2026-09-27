import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppSettings.studyGroupNewWordCountKey) private var studyGroupNewWordCount = AppSettings.defaultStudyGroupNewWordCount
    @AppStorage(AppSettings.reviewGroupWordCountKey) private var reviewGroupWordCount = AppSettings.defaultReviewGroupWordCount
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        PageScaffold(title: "设置", subtitle: "调整学习数量与管理本地数据。") {
            Form {
                Section("学习") {
                    Stepper(value: studyGroupNewWordCountBinding, in: AppSettings.minimumStudyGroupNewWordCount...AppSettings.maximumStudyGroupNewWordCount) {
                        LabeledContent("每组学习新词数量") { Text("\(studyGroupNewWordCountBinding.wrappedValue)").monospacedDigit() }
                    }
                    Stepper(value: reviewGroupWordCountBinding, in: AppSettings.minimumReviewGroupWordCount...AppSettings.maximumReviewGroupWordCount) {
                        LabeledContent("每组复习数量") { Text("\(reviewGroupWordCountBinding.wrappedValue)").monospacedDigit() }
                    }
                    LabeledContent("学习顺序") {
                        Text("每组自动随机")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("数据") {
                    Button { viewModel.prepareFullBackupExport(context: modelContext) } label: {
                        Label("导出备份", systemImage: "externaldrive")
                    }
                    .disabled(viewModel.isImportingBackup)
                    Button { viewModel.isBackupImporterPresented = true } label: {
                        Label("导入备份", systemImage: "tray.and.arrow.down")
                    }
                    .disabled(viewModel.isImportingBackup)
                    Button { viewModel.prepareExport(context: modelContext) } label: {
                        Label("导出词书 CSV", systemImage: "square.and.arrow.up")
                    }
                    .disabled(viewModel.isImportingBackup)
                    if viewModel.isImportingBackup {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text(viewModel.backupImportStatus ?? "正在导入备份…")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Text("备份包含词书、词条、学习进度与复习记录。导入前会要求选择合并策略。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .padding(24)
        }
        .fileExporter(
            isPresented: $viewModel.isExporterPresented,
            document: viewModel.exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "kotoba_vocabulary.csv"
        ) { viewModel.handleExportCompletion($0) }
        .fileExporter(
            isPresented: $viewModel.isBackupExporterPresented,
            document: viewModel.backupDocument,
            contentType: .json,
            defaultFilename: viewModel.defaultBackupFileName
        ) { viewModel.handleBackupExportCompletion($0) }
        .fileImporter(
            isPresented: $viewModel.isBackupImporterPresented,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { viewModel.prepareBackupImport(from: url) }
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $viewModel.isBackupImportConfirmationPresented) {
            BackupImportConfirmationSheet(
                strategy: $viewModel.backupImportStrategy,
                isImporting: viewModel.isImportingBackup,
                statusText: viewModel.backupImportStatus,
                onCancel: { viewModel.cancelBackupImport() },
                onConfirm: { viewModel.confirmBackupImport(context: modelContext) }
            )
        }
        .alert("设置操作失败", isPresented: messageBinding($viewModel.errorMessage)) {
            Button("好") { viewModel.errorMessage = nil }
        } message: { Text(viewModel.errorMessage ?? "") }
        .alert("操作完成", isPresented: messageBinding($viewModel.successMessage)) {
            Button("好") { viewModel.successMessage = nil }
        } message: { Text(viewModel.successMessage ?? "") }
    }

    private var studyGroupNewWordCountBinding: Binding<Int> {
        Binding {
            AppSettings.clampedStudyGroupNewWordCount(studyGroupNewWordCount)
        } set: { studyGroupNewWordCount = AppSettings.clampedStudyGroupNewWordCount($0) }
    }

    private var reviewGroupWordCountBinding: Binding<Int> {
        Binding {
            AppSettings.clampedReviewGroupWordCount(reviewGroupWordCount)
        } set: { reviewGroupWordCount = AppSettings.clampedReviewGroupWordCount($0) }
    }

    private func messageBinding(_ message: Binding<String?>) -> Binding<Bool> {
        Binding {
            message.wrappedValue != nil
        } set: { isPresented in
            if !isPresented { message.wrappedValue = nil }
        }
    }
}

private struct BackupImportConfirmationSheet: View {
    @Binding var strategy: KotobaBackupImportStrategy
    let isImporting: Bool
    let statusText: String?
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("导入备份").font(.title3.weight(.semibold))
            Text("导入会修改本地词书、学习进度和复习记录。请选择处理重复数据的方式。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("导入策略", selection: $strategy) {
                ForEach(KotobaBackupImportStrategy.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(isImporting)
            if isImporting {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(statusText ?? "正在导入备份…")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
                }
                .padding(24)
            }

            Divider()
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isImporting)
                Button("确认导入", action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isImporting)
            }
            .padding(16)
            .background(.bar)
        }
        .frame(minWidth: 360, idealWidth: 460, maxWidth: 560, minHeight: 260, idealHeight: 340, maxHeight: 520)
        .interactiveDismissDisabled(isImporting)
    }
}

#Preview {
    SettingsView()
        .modelContainer(PreviewModelContainer.make())
        .frame(width: 700, height: 500)
}
