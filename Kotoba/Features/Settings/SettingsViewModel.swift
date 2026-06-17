//
//  SettingsViewModel.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import Combine
import Foundation
import SwiftData

@MainActor
final class SettingsViewModel: ObservableObject {
    static let clearAllDataConfirmationPhrase = "清空全部数据"

    @Published var exportDocument: VocabularyCSVDocument?
    @Published var isExporterPresented = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var isFirstClearConfirmationPresented = false
    @Published var isFinalClearConfirmationPresented = false
    @Published var clearConfirmationText = ""
    @Published var isTestingLMStudio = false
    @Published var lmStudioStatusMessage: String?

    private let exportService: VocabularyCSVExportService
    private let dataManagementService: DataManagementService

    init(
        exportService: VocabularyCSVExportService? = nil,
        dataManagementService: DataManagementService? = nil
    ) {
        self.exportService = exportService ?? VocabularyCSVExportService()
        self.dataManagementService = dataManagementService ?? DataManagementService()
    }

    var canClearAllData: Bool {
        clearConfirmationText == Self.clearAllDataConfirmationPhrase
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

    func requestClearAllData() {
        clearConfirmationText = ""
        isFirstClearConfirmationPresented = true
    }

    func continueToFinalClearConfirmation() {
        clearConfirmationText = ""
        isFinalClearConfirmationPresented = true
    }

    func cancelFinalClearConfirmation() {
        clearConfirmationText = ""
        isFinalClearConfirmationPresented = false
    }

    func clearAllData(context: ModelContext) {
        guard canClearAllData else {
            return
        }

        do {
            try dataManagementService.clearAllData(in: context)
            clearConfirmationText = ""
            isFinalClearConfirmationPresented = false
            successMessage = "全部本地学习数据已清空。"
        } catch {
            errorMessage = "清空数据失败：\(error.localizedDescription)"
        }
    }

    func testLMStudioConnection(
        baseURLString: String,
        modelName: String,
        timeout: Double
    ) {
        guard !isTestingLMStudio else {
            return
        }

        guard let baseURL = URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = "LM Studio URL 格式无效。"
            return
        }

        isTestingLMStudio = true
        lmStudioStatusMessage = nil

        Task {
            do {
                let provider = LMStudioConjugationProvider(
                    baseURL: baseURL,
                    modelName: modelName.trimmingCharacters(in: .whitespacesAndNewlines),
                    timeout: AppSettings.clampedLMStudioTimeout(timeout)
                )
                let status = try await provider.testConnection()
                lmStudioStatusMessage = status.message
                successMessage = status.message
            } catch {
                lmStudioStatusMessage = "连接失败：\(error.localizedDescription)"
                errorMessage = lmStudioStatusMessage
            }

            isTestingLMStudio = false
        }
    }
}
