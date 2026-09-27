//
//  KotobaBackupDocument.swift
//  Kotoba
//
//  Created by Codex on 2026/6/18.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct KotobaBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [UTType.json]
    }

    static var writableContentTypes: [UTType] {
        [UTType.json]
    }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
