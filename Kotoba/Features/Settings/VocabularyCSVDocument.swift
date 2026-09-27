//
//  VocabularyCSVDocument.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct VocabularyCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [csvContentType]
    }

    static var writableContentTypes: [UTType] {
        [csvContentType]
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

    private static var csvContentType: UTType {
        .commaSeparatedText
    }
}
