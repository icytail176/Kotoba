//
//  ExampleHighlightingService.swift
//  Kotoba
//
//  Created by Codex on 2026/6/17.
//

import Foundation

struct HighlightedTextSegment: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isHighlighted: Bool

    static func == (lhs: HighlightedTextSegment, rhs: HighlightedTextSegment) -> Bool {
        lhs.text == rhs.text && lhs.isHighlighted == rhs.isHighlighted
    }
}

struct ExampleHighlightingService {
    func segments(in text: String, target: String) -> [HighlightedTextSegment] {
        guard !text.isEmpty, !target.isEmpty else {
            return [HighlightedTextSegment(text: text, isHighlighted: false)]
        }

        var segments: [HighlightedTextSegment] = []
        var searchStart = text.startIndex

        while searchStart < text.endIndex,
              let range = text.range(of: target, range: searchStart..<text.endIndex) {
            if range.lowerBound > searchStart {
                segments.append(
                    HighlightedTextSegment(
                        text: String(text[searchStart..<range.lowerBound]),
                        isHighlighted: false
                    )
                )
            }

            segments.append(
                HighlightedTextSegment(
                    text: String(text[range]),
                    isHighlighted: true
                )
            )
            searchStart = range.upperBound
        }

        if searchStart < text.endIndex {
            segments.append(
                HighlightedTextSegment(
                    text: String(text[searchStart..<text.endIndex]),
                    isHighlighted: false
                )
            )
        }

        return segments.isEmpty ? [HighlightedTextSegment(text: text, isHighlighted: false)] : segments
    }
}
