//
//  VocabularyImportViewModel.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import Combine
import Foundation
import SwiftData

enum VocabularyImportTargetMode: String, CaseIterable, Identifiable {
    case newWordBook
    case existingWordBook

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newWordBook:
            return "新建词书"
        case .existingWordBook:
            return "导入到已有词书"
        }
    }
}

@MainActor
final class VocabularyImportViewModel: ObservableObject {
    @Published var preview: VocabularyImportPreview?
    @Published var result: VocabularyImportResult?
    @Published var qualityReport: VocabularyImportQualityReport?
    @Published var duplicateHandling: VocabularyDuplicateHandling = .skip
    @Published var errorMessage: String?
    @Published private(set) var isImporting = false
    @Published var isTargetConfigurationPresented = false
    @Published var targetMode: VocabularyImportTargetMode = .newWordBook
    @Published var newWordBookName = ""
    @Published var newWordBookDescription = ""
    @Published var existingWordBookID = ""
    @Published private(set) var availableWordBooks: [WordBook] = []

    private let service: VocabularyCSVImportService
    private let qualityService: VocabularyImportQualityService
    private let wordBookService: WordBookService
    private var pendingFileData: Data?
    private var pendingFileName = ""
    private var pendingTarget: VocabularyImportTarget?

    init(
        service: VocabularyCSVImportService? = nil,
        qualityService: VocabularyImportQualityService? = nil,
        wordBookService: WordBookService? = nil
    ) {
        self.service = service ?? VocabularyCSVImportService()
        self.qualityService = qualityService ?? VocabularyImportQualityService()
        self.wordBookService = wordBookService ?? WordBookService()
    }

    var canConfirmTarget: Bool {
        switch targetMode {
        case .newWordBook:
            return !newWordBookName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .existingWordBook:
            return UUID(uuidString: existingWordBookID) != nil
        }
    }

    func prepareFile(from url: URL, context: ModelContext, preferredWordBookID: String = "") {
        result = nil
        qualityReport = nil
        errorMessage = nil
        duplicateHandling = .skip
        pendingTarget = nil

        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            pendingFileData = try Data(contentsOf: url)
            pendingFileName = url.lastPathComponent
            availableWordBooks = try wordBookService.fetchWordBooks(in: context)
            newWordBookName = defaultWordBookName(for: url)
            newWordBookDescription = ""

            if let preferredID = UUID(uuidString: preferredWordBookID),
               availableWordBooks.contains(where: { $0.id == preferredID }) {
                targetMode = .existingWordBook
                existingWordBookID = preferredID.uuidString
            } else if let firstBook = availableWordBooks.first {
                targetMode = .existingWordBook
                existingWordBookID = firstBook.id.uuidString
            } else {
                targetMode = .newWordBook
                existingWordBookID = ""
            }

            preview = nil
            qualityReport = nil
            isTargetConfigurationPresented = true
        } catch {
            preview = nil
            qualityReport = nil
            pendingFileData = nil
            errorMessage = error.localizedDescription
        }
    }

    func confirmTargetSelection(context: ModelContext) {
        guard let pendingFileData else {
            return
        }

        do {
            let target = try makeTarget()
            let targetWordBook = try targetWordBook(for: target, context: context)
            let importPreview = try service.makePreview(
                from: pendingFileData,
                fileName: pendingFileName,
                context: context,
                targetWordBook: targetWordBook,
                createsNewWordBook: targetMode == .newWordBook
            )
            preview = importPreview
            qualityReport = try qualityService.makeReport(
                preview: importPreview,
                context: context,
                targetWordBook: targetWordBook
            )
            pendingTarget = target
            isTargetConfigurationPresented = false
        } catch {
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
                context: context,
                target: pendingTarget
            )
            self.preview = nil
            pendingFileData = nil
            pendingTarget = nil
            result = VocabularyImportResult(
                insertedCount: importResult.insertedCount,
                updatedCount: importResult.updatedCount,
                skippedDuplicateCount: importResult.skippedDuplicateCount,
                ignoredErrorCount: importResult.ignoredErrorCount,
                wordBookID: importResult.wordBookID,
                wordBookName: importResult.wordBookName,
                qualityReport: qualityReport
            )
        } catch {
            errorMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    func cancelPreview() {
        preview = nil
        qualityReport = nil
    }

    func cancelTargetSelection() {
        isTargetConfigurationPresented = false
        pendingFileData = nil
        pendingTarget = nil
        qualityReport = nil
    }

    func dismissResult() {
        result = nil
        qualityReport = nil
    }

    private func makeTarget() throws -> VocabularyImportTarget {
        switch targetMode {
        case .newWordBook:
            var draft = WordBookDraft()
            draft.name = newWordBookName
            draft.bookDescription = newWordBookDescription
            let sanitizedDraft = try wordBookService.validateAndSanitize(draft)
            return .newWordBook(
                name: sanitizedDraft.name,
                description: sanitizedDraft.bookDescription
            )
        case .existingWordBook:
            guard let id = UUID(uuidString: existingWordBookID) else {
                throw WordBookValidationError.missingName
            }

            return .existingWordBook(id)
        }
    }

    private func targetWordBook(for target: VocabularyImportTarget, context: ModelContext) throws -> WordBook? {
        switch target {
        case .newWordBook:
            return nil
        case .existingWordBook(let id):
            let books = try wordBookService.fetchWordBooks(in: context)
            return books.first { $0.id == id }
        }
    }

    private func defaultWordBookName(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return name.isEmpty ? "新词书" : name
    }
}
