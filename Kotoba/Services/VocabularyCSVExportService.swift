//
//  VocabularyCSVExportService.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import Foundation
import SwiftData

struct VocabularyExportRow: Equatable {
    let expression: String
    let reading: String
    let meaningChinese: String
    let partOfSpeech: String
    let exampleJapanese: String
    let exampleChinese: String
    let jlptLevel: String
    let tags: [String]
}

struct VocabularyCSVExportService {
    private static let headers = [
        "expression",
        "reading",
        "meaningChinese",
        "partOfSpeech",
        "exampleJapanese",
        "exampleChinese",
        "jlptLevel",
        "tags"
    ]

    @MainActor
    func exportCSV(in context: ModelContext) throws -> String {
        let descriptor = FetchDescriptor<VocabularyWord>(
            sortBy: [
                SortDescriptor(\.japanese, order: .forward),
                SortDescriptor(\.kana, order: .forward)
            ]
        )
        let words = try context.fetch(descriptor)

        return makeCSV(from: words.map { word in
            VocabularyExportRow(
                expression: word.japanese,
                reading: word.kana,
                meaningChinese: word.chineseMeaning,
                partOfSpeech: word.partOfSpeech,
                exampleJapanese: word.exampleJapanese,
                exampleChinese: word.exampleChinese,
                jlptLevel: word.jlptLevel,
                tags: word.tags
            )
        })
    }

    func makeCSV(from rows: [VocabularyExportRow]) -> String {
        var lines = [Self.headers.joined(separator: ",")]

        for row in rows {
            lines.append([
                row.expression,
                row.reading,
                row.meaningChinese,
                row.partOfSpeech,
                row.exampleJapanese,
                row.exampleChinese,
                row.jlptLevel,
                row.tags.joined(separator: ";")
            ]
            .map(escape)
            .joined(separator: ","))
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func escape(_ value: String) -> String {
        let escapedValue = value.replacingOccurrences(of: "\"", with: "\"\"")
        let requiresQuotes = escapedValue.contains(",")
            || escapedValue.contains("\"")
            || escapedValue.contains("\n")
            || escapedValue.contains("\r")

        return requiresQuotes ? "\"\(escapedValue)\"" : escapedValue
    }
}
