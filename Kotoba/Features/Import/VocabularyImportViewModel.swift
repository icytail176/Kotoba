//
//  VocabularyImportViewModel.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import Combine
import Foundation
import SwiftData

@MainActor
final class VocabularyImportViewModel: ObservableObject {
    @Published var preview: VocabularyImportPreview?
    @Published var result: VocabularyImportResult?
    @Published var duplicateHandling: VocabularyDuplicateHandling = .skip
    @Published var errorMessage: String?
    @Published private(set) var isImporting = false

    private let service: VocabularyCSVImportService

    init(service: VocabularyCSVImportService? = nil) {
        self.service = service ?? VocabularyCSVImportService()
    }

    func loadPreview(from url: URL, context: ModelContext) {
        result = nil
        errorMessage = nil
        duplicateHandling = .skip

        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            preview = try service.makePreview(
                from: data,
                fileName: url.lastPathComponent,
                context: context
            )
        } catch {
            preview = nil
            errorMessage = error.localizedDescription
        }
    }

    func confirmImport(context: ModelContext) {
        guard let preview else {
            return
        }

        isImporting = true
        defer { isImporting = false }

        do {
            let importResult = try service.importRows(
                from: preview,
                duplicateHandling: duplicateHandling,
                context: context
            )
            self.preview = nil
            result = importResult
        } catch {
            errorMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    func cancelPreview() {
        preview = nil
    }

    func dismissResult() {
        result = nil
    }
}
