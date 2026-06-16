//
//  CSVParser.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import Foundation

struct CSVTable: Equatable {
    let headers: [String]
    let rows: [CSVRecord]
}

struct CSVRecord: Equatable {
    let lineNumber: Int
    let fields: [String]
}

enum CSVParserError: LocalizedError, Equatable {
    case emptyFile
    case unterminatedQuotedField(line: Int)

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "CSV 文件为空。"
        case .unterminatedQuotedField(let line):
            return "第 \(line) 行存在未闭合的双引号。"
        }
    }
}

struct CSVParser {
    func parse(_ text: String) throws -> CSVTable {
        let records = try parseRecords(text)
        guard let headerRecord = records.first else {
            throw CSVParserError.emptyFile
        }

        var headers = headerRecord.fields
        if let firstHeader = headers.first {
            headers[0] = firstHeader.removingUTF8BOM
        }

        return CSVTable(headers: headers, rows: Array(records.dropFirst()))
    }

    private func parseRecords(_ text: String) throws -> [CSVRecord] {
        var records: [CSVRecord] = []
        var fields: [String] = []
        var field = ""
        var isInsideQuotes = false
        var lineNumber = 1
        var recordStartLine = 1
        var index = text.startIndex
        var hasRecordContent = false

        while index < text.endIndex {
            let character = text[index]

            if isInsideQuotes {
                if character == "\"" {
                    let nextIndex = text.index(after: index)
                    if nextIndex < text.endIndex, text[nextIndex] == "\"" {
                        field.append("\"")
                        index = text.index(after: nextIndex)
                    } else {
                        isInsideQuotes = false
                        index = nextIndex
                    }
                } else if character.isCSVNewline {
                    appendNewline(character, from: text, index: &index, lineNumber: &lineNumber, to: &field)
                } else {
                    field.append(character)
                    index = text.index(after: index)
                }

                hasRecordContent = true
                continue
            }

            if character == "\"" && field.isEmpty {
                isInsideQuotes = true
                hasRecordContent = true
                index = text.index(after: index)
            } else if character == "," {
                fields.append(field)
                field = ""
                hasRecordContent = true
                index = text.index(after: index)
            } else if character.isCSVNewline {
                fields.append(field)
                appendRecordIfNeeded(fields: fields, lineNumber: recordStartLine, to: &records)
                fields = []
                field = ""
                hasRecordContent = false
                advancePastRecordNewline(character, from: text, index: &index, lineNumber: &lineNumber)
                recordStartLine = lineNumber
            } else {
                field.append(character)
                hasRecordContent = true
                index = text.index(after: index)
            }
        }

        if isInsideQuotes {
            throw CSVParserError.unterminatedQuotedField(line: recordStartLine)
        }

        if hasRecordContent || !fields.isEmpty || !field.isEmpty {
            fields.append(field)
            appendRecordIfNeeded(fields: fields, lineNumber: recordStartLine, to: &records)
        }

        return records
    }

    private func appendRecordIfNeeded(fields: [String], lineNumber: Int, to records: inout [CSVRecord]) {
        guard fields.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return
        }

        records.append(CSVRecord(lineNumber: lineNumber, fields: fields))
    }

    private func appendNewline(
        _ character: Character,
        from text: String,
        index: inout String.Index,
        lineNumber: inout Int,
        to field: inout String
    ) {
        if character == "\r" {
            let nextIndex = text.index(after: index)
            if nextIndex < text.endIndex, text[nextIndex] == "\n" {
                field.append("\n")
                index = text.index(after: nextIndex)
            } else {
                field.append("\n")
                index = nextIndex
            }
        } else {
            field.append(character)
            index = text.index(after: index)
        }

        lineNumber += 1
    }

    private func advancePastRecordNewline(
        _ character: Character,
        from text: String,
        index: inout String.Index,
        lineNumber: inout Int
    ) {
        if character == "\r" {
            let nextIndex = text.index(after: index)
            if nextIndex < text.endIndex, text[nextIndex] == "\n" {
                index = text.index(after: nextIndex)
            } else {
                index = nextIndex
            }
        } else {
            index = text.index(after: index)
        }

        lineNumber += 1
    }
}

private extension Character {
    var isCSVNewline: Bool {
        self == "\n" || self == "\r"
    }
}

private extension String {
    var removingUTF8BOM: String {
        if hasPrefix("\u{FEFF}") {
            return String(dropFirst())
        }

        return self
    }
}
