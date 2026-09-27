import Foundation
import XCTest
@testable import Kotoba

@MainActor
final class BuiltInConjugationAuditTests: XCTestCase {
    private struct Row {
        let level: String
        let line: Int
        let expression: String
        let reading: String
        let partOfSpeech: String
    }

    private let concreteClassTokens: [String: ConjugationClass] = [
        "一段动词": .ichidanVerb,
        "一段動詞": .ichidanVerb,
        "五段动词": .godanVerb,
        "五段動詞": .godanVerb,
        "サ变动词": .suruVerb,
        "サ変動詞": .suruVerb,
        "する动词": .suruVerb,
        "する動詞": .suruVerb,
        "カ变动词": .kuruVerb,
        "カ変動詞": .kuruVerb,
        "い形容词": .iAdjective,
        "い形容詞": .iAdjective,
        "な形容词": .naAdjective,
        "な形容詞": .naAdjective,
    ]

    func testEveryBundledRowIsSafeAndEveryConcreteCandidateIsHandled() throws {
        let rows = try loadRows()
        let deliberatelyUnsupported = Set([
            "N5\u{1F}くださる\u{1F}くださる",
            "N5\u{1F}いらっしゃる\u{1F}いらっしゃる",
            "N5\u{1F}下さい\u{1F}ください",
            "N4\u{1F}なさる\u{1F}なさる",
            "N3\u{1F}おっしゃる\u{1F}おっしゃる",
            "N2\u{1F}問う\u{1F}とう",
        ])

        XCTAssertEqual(rows.count, 10_609)
        var candidateCount = 0
        var generatedCandidateCount = 0

        for row in rows {
            let context = "\(row.level):\(row.line) \(row.expression)/\(row.reading)"
            XCTAssertFalse(row.expression.isEmpty, context)
            XCTAssertFalse(row.reading.isEmpty, context)

            let tokens = row.partOfSpeech.split(separator: "/").map(String.init)
            let classes = Set(tokens.compactMap { concreteClassTokens[$0] })

            let marksConjugatable = !classes.isEmpty || tokens.contains(where: {
                $0.contains("动词") || $0.contains("動詞") || $0.contains("形容词") || $0.contains("形容詞")
            })
            let generated = generate(row.expression, row.reading, row.partOfSpeech)

            if marksConjugatable {
                candidateCount += 1
                let key = "\(row.level)\u{1F}\(row.expression)\u{1F}\(row.reading)"
                if deliberatelyUnsupported.contains(key) {
                    XCTAssertNil(generated, "deliberately rejected form unexpectedly generated: \(context)")
                } else {
                    XCTAssertNotNil(generated, "conjugatable row was not generated: \(context)")
                }
            }

            guard let generated else { continue }
            if marksConjugatable { generatedCandidateCount += 1 }
            XCTAssertFalse(generated.forms.isEmpty, context)
            XCTAssertEqual(generated.forms.first(where: { $0.type == .dictionary })?.surface, row.expression, context)
            XCTAssertEqual(generated.forms.first(where: { $0.type == .dictionary })?.reading, row.reading, context)
            XCTAssertTrue(generated.forms.allSatisfy { !$0.surface.isEmpty && !$0.reading.isEmpty }, context)
            XCTAssertEqual(Set(generated.forms.map(\.type)).count, generated.forms.count, "duplicate formType: \(context)")
        }

        XCTAssertEqual(candidateCount, 4_823)
        XCTAssertEqual(generatedCandidateCount, 4_817)
    }

    func testCorrectedWordsHaveExternallyVerifiedClasses() throws {
        let fixtures: [(String, String, String, ConjugationClass)] = [
            ("来る", "くる", "动词/自动词/カ变动词/补助动词", .kuruVerb),
            ("やってくる", "やってくる", "动词/自动词/カ变动词", .kuruVerb),
            ("買い与える", "かいあたえる", "动词/他动词/一段动词", .ichidanVerb),
            ("擦り抜ける", "すりぬける", "动词/自动词/一段动词", .ichidanVerb),
            ("生まれ落ちる", "うまれおちる", "动词/自动词/一段动词", .ichidanVerb),
        ]

        for fixture in fixtures {
            XCTAssertEqual(
                try XCTUnwrap(generate(fixture.0, fixture.1, fixture.2)).conjugationClass,
                fixture.3,
                fixture.0
            )
        }
    }

    func testSpecialAndRuleBoundaryForms() throws {
        let fixtures: [(String, String, String, ConjugationClass, [ConjugationFormType: String])] = [
            ("いい", "いい", "い形容词", .iAdjective,
             [.dictionary: "いい", .polite: "いいです", .negative: "よくない", .past: "よかった", .teForm: "よくて", .conditional: "よければ", .adverbial: "よく"]),
            ("行く", "いく", "五段动词", .godanVerb,
             [.dictionary: "行く", .polite: "行きます", .negative: "行かない", .past: "行った", .teForm: "行って", .conditional: "行けば", .potential: "行ける", .volitional: "行こう", .imperative: "行け", .passive: "行かれる", .causative: "行かせる", .causativePassive: "行かせられる"]),
            ("来る", "くる", "カ变动词", .kuruVerb,
             [.dictionary: "来る", .polite: "来ます", .negative: "来ない", .past: "来た", .teForm: "来て", .conditional: "来れば", .potential: "来られる", .volitional: "来よう", .imperative: "来い", .passive: "来られる", .causative: "来させる", .causativePassive: "来させられる"]),
            ("する", "する", "サ变动词", .suruVerb,
             [.dictionary: "する", .polite: "します", .negative: "しない", .past: "した", .teForm: "して", .conditional: "すれば", .potential: "できる", .volitional: "しよう", .imperative: "しろ", .passive: "される", .causative: "させる", .causativePassive: "させられる"]),
            ("ある", "ある", "五段动词", .godanVerb,
             [.dictionary: "ある", .polite: "あります", .negative: "ない", .past: "あった", .teForm: "あって", .conditional: "あれば", .volitional: "あろう", .imperative: "あれ"]),
            ("やってくる", "やってくる", "カ变动词", .kuruVerb,
             [.polite: "やってきます", .negative: "やってこない", .past: "やってきた", .teForm: "やってきて", .imperative: "やってこい"]),
            ("買い与える", "かいあたえる", "一段动词", .ichidanVerb,
             [.polite: "買い与えます", .negative: "買い与えない", .teForm: "買い与えて"]),
            ("擦り抜ける", "すりぬける", "一段动词", .ichidanVerb,
             [.polite: "擦り抜けます", .past: "擦り抜けた", .teForm: "擦り抜けて"]),
            ("生まれ落ちる", "うまれおちる", "一段动词", .ichidanVerb,
             [.polite: "生まれ落ちます", .past: "生まれ落ちた", .teForm: "生まれ落ちて"]),
            ("着る", "きる", "一段动词", .ichidanVerb, [.polite: "着ます"]),
            ("いる", "いる", "一段动词", .ichidanVerb, [.polite: "います"]),
            ("変える", "かえる", "一段动词", .ichidanVerb, [.polite: "変えます"]),
            ("経る", "へる", "一段动词", .ichidanVerb, [.polite: "経ます"]),
            ("換える", "かえる", "一段动词", .ichidanVerb, [.polite: "換えます"]),
        ]

        for fixture in fixtures {
            let generated = try XCTUnwrap(generate(fixture.0, fixture.1, fixture.2), fixture.0)
            XCTAssertEqual(generated.conjugationClass, fixture.3, fixture.0)
            let actual = Dictionary(uniqueKeysWithValues: generated.forms.map { ($0.type, $0.surface) })
            for (type, expected) in fixture.4 {
                XCTAssertEqual(actual[type], expected, "\(fixture.0) \(type.rawValue)")
            }
            if fixture.0 == "ある" {
                XCTAssertEqual(generated.forms.count, fixture.4.count)
            }
        }
    }

    func testCautiouslyRejectedSpecialsRemainExplicitlyUnsupported() {
        let fixtures = [
            ("問う", "とう"), ("請う", "こう"), ("乞う", "こう"),
            ("いらっしゃる", "いらっしゃる"), ("おっしゃる", "おっしゃる"),
            ("くださる", "くださる"), ("なさる", "なさる"), ("ござる", "ござる"),
        ]
        for fixture in fixtures {
            XCTAssertNil(generate(fixture.0, fixture.1, "五段动词"), fixture.0)
        }
    }

    private func generate(_ expression: String, _ reading: String, _ partOfSpeech: String) -> GeneratedConjugation? {
        ConjugationEngine().generate(for: ConjugationGenerationRequest(
            wordID: UUID(),
            expression: expression,
            reading: reading,
            meaningChinese: "",
            partOfSpeech: partOfSpeech
        ))
    }

    private func loadRows() throws -> [Row] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Kotoba/Resources")
        let parser = CSVParser()
        var result: [Row] = []

        for definition in BuiltInWordBookDefinition.all {
            let text = try String(
                contentsOf: root.appendingPathComponent(definition.fileName),
                encoding: .utf8
            )
            let table = try parser.parse(text)
            XCTAssertEqual(table.headers, BuiltInWordBookService.requiredHeaders, definition.fileName)
            for record in table.rows {
                XCTAssertEqual(record.fields.count, 8, "\(definition.fileName):\(record.lineNumber)")
                result.append(Row(
                    level: definition.level,
                    line: record.lineNumber,
                    expression: record.fields[0].trimmingCharacters(in: .whitespacesAndNewlines),
                    reading: record.fields[1].trimmingCharacters(in: .whitespacesAndNewlines),
                    partOfSpeech: record.fields[3].trimmingCharacters(in: .whitespacesAndNewlines)
                ))
            }
        }
        return result
    }
}
