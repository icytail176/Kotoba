//
//  SettingsViewModel.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import Combine
import Foundation
import SwiftData

enum KotobaBackupExportKind {
    case full

    var successMessage: String {
        switch self {
        case .full:
            return "全部数据备份已导出。"
        }
    }

    var fileNamePrefix: String {
        switch self {
        case .full:
            return "Kotoba_Backup"
        }
    }
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var exportDocument: VocabularyCSVDocument?
    @Published var backupDocument: KotobaBackupDocument?
    @Published var isExporterPresented = false
    @Published var isBackupExporterPresented = false
    @Published var isBackupImporterPresented = false
    @Published var isBackupImportConfirmationPresented = false
    @Published var backupImportStrategy: KotobaBackupImportStrategy = .merge
    @Published private(set) var isImportingBackup = false
    @Published private(set) var backupImportStatus: String?
    @Published private(set) var backupExportKind: KotobaBackupExportKind = .full
    @Published var errorMessage: String?
    @Published var successMessage: String?

    private let exportService: VocabularyCSVExportService
    private let backupService: KotobaBackupService
    private var backupImporter: (any KotobaBackupImporting)?
    private var pendingBackupImportData: Data?
    private var backupExportTask: Task<Void, Never>?
    private var backupImportTask: Task<Void, Never>?

    init(
        exportService: VocabularyCSVExportService? = nil,
        backupService: KotobaBackupService? = nil,
        backupImporter: (any KotobaBackupImporting)? = nil
    ) {
        self.exportService = exportService ?? VocabularyCSVExportService()
        self.backupService = backupService ?? KotobaBackupService()
        self.backupImporter = backupImporter
    }

    var defaultBackupFileName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(backupExportKind.fileNamePrefix)_\(formatter.string(from: Date())).json"
    }

    func prepareExport(context: ModelContext) {
        do {
            let csv = try exportService.exportCSV(in: context)
            exportDocument = VocabularyCSVDocument(text: csv)
            isExporterPresented = true
            errorMessage = nil
        } catch {
            errorMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    func handleExportCompletion(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            successMessage = "词书 CSV 已导出。"
        case .failure(let error):
            errorMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    func prepareFullBackupExport(context: ModelContext) {
        backupExportTask?.cancel()
        do {
            let snapshot = try backupService.makeBackup(in: context)
            backupExportTask = Task { [weak self, snapshot] in
                do {
                    let data = try await Task.detached(priority: .userInitiated) {
                        try KotobaBackupService.encodeBackupSnapshot(snapshot)
                    }.value
                    guard !Task.isCancelled else { return }
                    self?.backupDocument = KotobaBackupDocument(data: data)
                    self?.backupExportKind = .full
                    self?.isBackupExporterPresented = true
                    self?.errorMessage = nil
                } catch {
                    guard !Task.isCancelled else { return }
                    self?.errorMessage = "备份导出失败：\(error.localizedDescription)"
                }
            }
        } catch {
            errorMessage = "备份导出失败：\(error.localizedDescription)"
        }
    }

    func handleBackupExportCompletion(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            successMessage = backupExportKind.successMessage
        case .failure(let error):
            errorMessage = "备份导出失败：\(error.localizedDescription)"
        }
    }

    func prepareBackupImport(from url: URL) {
        guard !isImportingBackup else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            try stageBackupImport(data: data)
        } catch {
            pendingBackupImportData = nil
            errorMessage = "备份文件无效：\(error.localizedDescription)"
        }
    }

    func stageBackupImport(data: Data) throws {
        guard !isImportingBackup else {
            throw KotobaBackupImportError.alreadyInProgress
        }

        _ = try backupService.decodeBackup(from: data)
        pendingBackupImportData = data
        backupImportStrategy = .merge
        isBackupImportConfirmationPresented = true
        errorMessage = nil
    }

    func cancelBackupImport() {
        guard !isImportingBackup else { return }
        pendingBackupImportData = nil
        isBackupImportConfirmationPresented = false
    }

    func confirmBackupImport(context: ModelContext) {
        guard !isImportingBackup, let pendingBackupImportData else {
            return
        }

        let importer = backupImporter ?? KotobaBackupImportCoordinator(modelContainer: context.container)
        backupImporter = importer
        let strategy = backupImportStrategy

        isImportingBackup = true
        backupImportStatus = "正在导入备份…"
        errorMessage = nil
        successMessage = nil

        backupImportTask = Task { [weak self, importer, pendingBackupImportData, strategy, context] in
            do {
                let result = try await importer.importBackup(
                from: pendingBackupImportData,
                    strategy: strategy
                )

                // SwiftData publishes saves from the sibling context. Processing
                // pending changes here ensures observation is delivered before
                // the success state is shown and subsequent screens re-fetch.
                context.processPendingChanges()
                StudyStatisticsService.invalidateCache()

                self?.pendingBackupImportData = nil
                self?.isBackupImportConfirmationPresented = false
                self?.successMessage = "备份导入完成：新增词书 \(result.insertedWordBookCount)，新增词条 \(result.insertedWordCount)，新增复习记录 \(result.insertedReviewLogCount)。"
            } catch {
                self?.errorMessage = "备份导入失败：\(error.localizedDescription)"
            }

            self?.isImportingBackup = false
            self?.backupImportStatus = nil
            self?.backupImportTask = nil
        }
    }

}
