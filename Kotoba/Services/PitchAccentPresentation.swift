import Foundation

struct PitchAccentPresentation: Equatable {
    let displayText: String
    let accessibilityText: String

    static func make(tags: [String]) -> Self? {
        guard let tag = tags.first(where: { $0.hasPrefix("音调:") }) else { return nil }
        let source = String(tag.dropFirst("音调:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return nil }

        let circledNumbers: [Character: Int] = [
            "⓪": 0, "①": 1, "②": 2, "③": 3, "④": 4, "⑤": 5,
            "⑥": 6, "⑦": 7, "⑧": 8, "⑨": 9, "⑩": 10,
            "⑪": 11, "⑫": 12, "⑬": 13, "⑭": 14, "⑮": 15,
            "⑯": 16, "⑰": 17, "⑱": 18, "⑲": 19, "⑳": 20
        ]
        var alternatives: [[[Int]]] = []
        for alternativeSource in source.split(separator: "、", omittingEmptySubsequences: false) {
            var components: [[Int]] = [[]]
            for character in alternativeSource {
                if character == "+" {
                    guard components.last?.isEmpty == false else { return nil }
                    components.append([])
                } else if let number = circledNumbers[character] {
                    components[components.count - 1].append(number)
                } else {
                    return nil
                }
            }
            guard components.allSatisfy({ !$0.isEmpty }) else { return nil }
            alternatives.append(components)
        }
        guard !alternatives.isEmpty else { return nil }

        let display = alternatives.map { components in
            components
                .map { $0.map(String.init).joined(separator: "/") }
                .joined(separator: "+")
        }
        .joined(separator: ", ")
        let spoken = alternatives.map { components in
            components
                .map { $0.map(String.init).joined(separator: "或") }
                .joined(separator: "加")
        }
        .joined(separator: "，或")
        return Self(
            displayText: "[\(display)]",
            accessibilityText: "音调型 \(spoken)"
        )
    }
}
