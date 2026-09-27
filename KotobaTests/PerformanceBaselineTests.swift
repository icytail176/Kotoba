import Foundation
import SwiftData
import XCTest
@testable import Kotoba

/// Repeatable performance sweep. There are deliberately no absolute time assertions:
/// the emitted samples are
/// compared on the same machine/build configuration before and after a change.
@MainActor
final class PerformanceBaselineTests: XCTestCase {
    private struct TimingSummary {
        let median: Double
        let minimum: Double
        let maximum: Double
        let p90: Double
    }

    func testPerformanceBaseline() throws {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        try benchmarkBuiltIn(now: now)
        try benchmarkHomeAndWordbook(now: now)
        try benchmarkCSV()
        try benchmarkBackup(now: now)
        try benchmarkStatistics(now: now)
        try benchmarkWordbookSummary(now: now)
    }

    func testBuiltInSeedPhaseProfileOnTemporaryDiskStores() throws {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let resourceDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Kotoba/Resources", isDirectory: true)
        var runs: [[String: Double]] = []

        for _ in 0..<5 {
            let root = URL.temporaryDirectory
                .appendingPathComponent("KotobaSeedPhase-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }

            runs.append(
                try runDiskSeedProfile(
                    storeURL: root.appendingPathComponent("seed.store"),
                    resourceDirectory: resourceDirectory,
                    now: now
                )
            )
        }

        emitPhaseMedians(prefix: "KOTOBA_SEED_PHASE", runs: runs)
    }

    func testBackupImportPhaseProfile() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

        for wordCount in [100, 1_000, 10_000] {
            let backup = makeBackup(wordCount: wordCount, now: now)
            let data = try KotobaBackupService.encodeBackupSnapshot(backup)
            var runs: [[String: Double]] = []

            for _ in 0..<3 {
                let container = try makeInMemoryTestContainer()
                let importer = KotobaBackupImportCoordinator(modelContainer: container)
                let importTask = Task {
                    try await importer.profileImportBackup(from: data, strategy: .merge)
                }
                let heartbeatStart = ContinuousClock.now
                await Task.yield()
                let mainActorBlocked = milliseconds(heartbeatStart.duration(to: .now))
                let profile = try await importTask.value
                XCTAssertEqual(profile.result.insertedWordCount, wordCount)
                XCTAssertEqual(profile.result.insertedProgressCount, wordCount)
                XCTAssertEqual(profile.result.insertedReviewLogCount, wordCount)
                var phases = profile.phaseMilliseconds
                phases["total"] = profile.totalMilliseconds
                phases["main_actor_blocked"] = mainActorBlocked
                runs.append(phases)
            }

            emitPhaseMedians(prefix: "KOTOBA_BACKUP_IMPORT_\(wordCount)", runs: runs)
        }
    }

    private func runDiskSeedProfile(
        storeURL: URL,
        resourceDirectory: URL,
        now: Date
    ) throws -> [String: Double] {
        let suiteName = "KotobaSeedPhase.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var phases: [String: Double] = [:]
        let service = BuiltInWordBookService(
            dataProvider: { definition in
                try Data(contentsOf: resourceDirectory.appendingPathComponent(definition.fileName))
            },
            etymologyDataProvider: {
                try Data(contentsOf: resourceDirectory.appendingPathComponent("builtin_loanword_etymology.csv"))
            },
            userDefaults: defaults,
            phaseRecorder: { phase, elapsed in
                phases[phase, default: 0] += self.milliseconds(elapsed)
            }
        )
        let container = try KotobaStore.makeContainer(at: storeURL)
        let result = try service.loadIfNeeded(in: container.mainContext, now: now)
        XCTAssertEqual(result.reduce(0) { $0 + $1.wordCount }, 10_609)
        return phases
    }

    private func emitPhaseMedians(prefix: String, runs: [[String: Double]]) {
        let phaseNames = Set(runs.flatMap(\.keys)).sorted()
        for phase in phaseNames {
            let values = runs.compactMap { $0[phase] }.sorted()
            guard !values.isEmpty else { continue }
            let median = values[values.count / 2]
            let minimum = values[0]
            let maximum = values[values.count - 1]
            let p90Index = min(values.count - 1, Int(ceil(Double(values.count) * 0.9)) - 1)
            let message = String(
                format: "%@ %@ median=%.3fms min=%.3fms max=%.3fms p90=%.3fms",
                prefix,
                phase.replacingOccurrences(of: " ", with: "_"),
                median,
                minimum,
                maximum,
                values[p90Index]
            )
            print(message)
            XCTContext.runActivity(named: message) { _ in }
        }
    }

    private func benchmarkBuiltIn(now: Date) throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "KotobaPerformanceBaseline"))
        defaults.removePersistentDomain(forName: "KotobaPerformanceBaseline")
        let resourceDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Kotoba/Resources", isDirectory: true)
        let service = BuiltInWordBookService(
            dataProvider: { definition in
                try Data(contentsOf: resourceDirectory.appendingPathComponent(definition.fileName))
            },
            etymologyDataProvider: {
                try Data(contentsOf: resourceDirectory.appendingPathComponent("builtin_loanword_etymology.csv"))
            },
            userDefaults: defaults
        )

        let firstSeed = try sample(iterations: 5, warmUp: 0) {
            defaults.removePersistentDomain(forName: "KotobaPerformanceBaseline")
            let container = try makeInMemoryTestContainer()
            _ = try service.loadIfNeeded(in: container.mainContext, now: now)
        }
        emit("built_in_first_seed_10609", firstSeed)

        defaults.removePersistentDomain(forName: "KotobaPerformanceBaseline")
        let container = try makeInMemoryTestContainer()
        _ = try service.loadIfNeeded(in: container.mainContext, now: now)
        let fastPath = try sample {
            _ = try service.loadIfNeeded(in: container.mainContext, now: now)
        }
        emit("built_in_fast_path_10609", fastPath)
    }

    private func benchmarkHomeAndWordbook(now: Date) throws {
        let container = try makeInMemoryTestContainer()
        let book = WordBook(name: "Performance 4000")
        container.mainContext.insert(book)
        for index in 0..<4_000 {
            let word = makeWord(index: index, book: book, now: now)
            container.mainContext.insert(word)
        }
        try container.mainContext.save()

        let home = try sample {
            _ = try HomeDashboardService().makeSnapshot(
                in: container.mainContext,
                selectedIDString: book.id.uuidString,
                now: now
            )
        }
        emit("home_large_book_4000", home)

        var filters = WordbookFilters()
        filters.tag = "even"
        for page in [1, 10, 30, 50] {
            let timing = try sample {
                _ = try WordbookService().fetchWordPage(
                    in: container.mainContext,
                    scopedWordBookID: book.id,
                    filters: filters,
                    offset: (page - 1) * 50,
                    limit: 50
                )
            }
            emit("word_management_tag_page_\(page)", timing)
        }
    }

    private func benchmarkCSV() throws {
        let container = try makeInMemoryTestContainer()
        for rowCount in [1_000, 10_000] {
            let data = makeCSV(rowCount: rowCount)
            let timing = try sample {
                _ = try VocabularyCSVImportService().makePreview(
                    from: data,
                    fileName: "performance-\(rowCount).csv",
                    context: container.mainContext,
                    createsNewWordBook: true
                )
            }
            emit("csv_preview_\(rowCount)", timing)
        }
    }

    private func benchmarkBackup(now: Date) throws {
        for wordCount in [1_000, 10_000] {
            let backup = makeBackup(wordCount: wordCount, now: now)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(backup)

            let encode = try sample { _ = try encoder.encode(backup) }
            emit("backup_encode_\(wordCount)", encode)

            let decode = try sample {
                _ = try KotobaBackupService().decodeBackup(from: data)
            }
            emit("backup_decode_\(wordCount)", decode)
        }
    }

    private func benchmarkStatistics(now: Date) throws {
        for logCount in [10_000, 50_000] {
            let wordCount = min(10_000, max(1_000, logCount / 5))
            let words = (0..<wordCount).map {
                StudyWordSnapshot(
                    id: deterministicUUID($0),
                    expression: "単語\($0)",
                    reading: "たんご\($0)",
                    meaningChinese: "词语\($0)"
                )
            }
            let logs = (0..<logCount).map { index in
                StudyLogSnapshot(
                    id: deterministicUUID(index + 100_000),
                    wordID: words[index % words.count].id,
                    reviewedAt: now.addingTimeInterval(TimeInterval(-(index % 120) * 86_400)),
                    rating: index.isMultiple(of: 7) ? .again : .good,
                    previousState: index.isMultiple(of: 5) ? .new : .review
                )
            }
            let input = StudyStatisticsInput(logs: logs, words: words)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3_600)!
            let timing = sample {
                _ = StudyStatisticsCalculator().calculate(input: input, calendar: calendar, now: now)
            }
            emit("statistics_calculate_\(logCount)", timing)
        }
    }

    private func benchmarkWordbookSummary(now: Date) throws {
        let container = try makeInMemoryTestContainer()
        let books = (0..<5).map { WordBook(name: "Book \($0)") }
        books.forEach(container.mainContext.insert)
        for index in 0..<10_000 {
            container.mainContext.insert(makeWord(index: index, book: books[index % books.count], now: now))
        }
        try container.mainContext.save()
        let timing = try sample {
            _ = try WordBookService().summaries(
                for: books,
                in: container.mainContext,
                selectedIDString: books[0].id.uuidString,
                now: now
            )
        }
        emit("wordbook_summary_5_books_10000", timing)
    }

    private func makeWord(index: Int, book: WordBook, now: Date) -> VocabularyWord {
        let word = VocabularyWord(
            id: deterministicUUID(index + (book.name.hashValue & 0x7fff_ffff)),
            japanese: String(format: "単語%05d", index),
            kana: String(format: "たんご%05d", index),
            chineseMeaning: "词语 \(index)",
            partOfSpeech: index.isMultiple(of: 2) ? "名词" : "动词/五段动词",
            jlptLevel: "N3",
            exampleJapanese: "単語\(index)の例文です。",
            exampleChinese: "这是词语 \(index) 的例句。",
            tags: [index.isMultiple(of: 2) ? "even" : "odd"],
            createdAt: now,
            updatedAt: now,
            isFavorite: index.isMultiple(of: 10),
            wordBook: book
        )
        let state: LearningState = index.isMultiple(of: 4) ? .new : .review
        word.progress = LearningProgress(
            state: state,
            dueAt: index.isMultiple(of: 3) ? now.addingTimeInterval(-86_400) : now.addingTimeInterval(86_400),
            intervalDays: state == .review ? 4 : 0,
            reviewCount: state == .review ? 2 : 0,
            createdAt: now,
            updatedAt: now,
            word: word
        )
        return word
    }

    private func makeCSV(rowCount: Int) -> Data {
        var lines = ["expression,reading,meaningChinese,partOfSpeech,exampleJapanese,exampleChinese,jlptLevel,tags"]
        lines.reserveCapacity(rowCount + 1)
        for index in 0..<rowCount {
            lines.append("単語\(index),たんご\(index),词语\(index),名词,単語\(index)の例文,例句,N3,performance")
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    private func makeBackup(wordCount: Int, now: Date) -> KotobaBackupFile {
        let bookID = deterministicUUID(900_000)
        let words = (0..<wordCount).map { index in
            BackupVocabularyWord(
                id: deterministicUUID(index),
                japanese: "単語\(index)",
                kana: "たんご\(index)",
                chineseMeaning: "词语\(index)",
                partOfSpeech: "名词",
                jlptLevel: "N3",
                exampleJapanese: "単語\(index)の例文",
                exampleChinese: "例句",
                tags: ["performance"],
                createdAt: now,
                updatedAt: now,
                isArchived: false,
                isFavorite: false,
                wordBookID: bookID,
                loanwordSourceTerm: nil,
                loanwordSourceLanguageCode: nil,
                loanwordIsWasei: false,
                loanwordIsPartial: false
            )
        }
        let progress = words.enumerated().map { index, word in
            BackupLearningProgress(
                id: deterministicUUID(index + 200_000),
                wordID: word.id,
                state: .review,
                dueAt: now,
                intervalDays: 4,
                reviewCount: 2,
                lapseCount: 0,
                lastReviewedAt: now,
                createdAt: now,
                updatedAt: now
            )
        }
        let logs = words.enumerated().map { index, word in
            BackupReviewLog(
                id: deterministicUUID(index + 400_000),
                wordID: word.id,
                reviewedAt: now,
                rating: .good,
                previousState: .review,
                nextState: .review,
                previousIntervalDays: 2,
                nextIntervalDays: 4,
                scheduledDueAt: now,
                errorTypes: [],
                typedAnswer: nil,
                expectedAnswer: nil,
                questionDirectionRawValue: nil,
                readingWrongCount: 0,
                spellingWrongCount: 0,
                repeatedWrongCount: 0
            )
        }
        return KotobaBackupFile(
            appVersion: "performance",
            schemaVersion: KotobaBackupService.schemaVersion,
            exportedAt: now,
            wordBooks: [
                BackupWordBook(
                    id: bookID,
                    name: "Performance",
                    bookDescription: "",
                    createdAt: now,
                    updatedAt: now,
                    isBuiltIn: false
                )
            ],
            vocabularyWords: words,
            learningProgress: progress,
            reviewLogs: logs
        )
    }

    private func deterministicUUID(_ value: Int) -> UUID {
        let suffix = String(format: "%012llx", UInt64(value) & 0x0000_ffff_ffff_ffff)
        return UUID(uuidString: "00000000-0000-4000-8000-\(suffix)")!
    }

    private func sample(
        iterations: Int = 7,
        warmUp: Int = 1,
        operation: () throws -> Void
    ) rethrows -> TimingSummary {
        for _ in 0..<warmUp { try operation() }
        var samples: [Double] = []
        samples.reserveCapacity(iterations)
        for _ in 0..<iterations {
            let start = ContinuousClock.now
            try operation()
            samples.append(milliseconds(start.duration(to: .now)))
        }
        let sorted = samples.sorted()
        let p90Index = min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.9)) - 1)
        return TimingSummary(
            median: sorted[sorted.count / 2],
            minimum: sorted[0],
            maximum: sorted[sorted.count - 1],
            p90: sorted[p90Index]
        )
    }

    private func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }

    private func emit(_ name: String, _ timing: TimingSummary) {
        let message = String(
            format: "KOTOBA_PERF %@ median=%.3fms min=%.3fms max=%.3fms p90=%.3fms",
            name,
            timing.median,
            timing.minimum,
            timing.maximum,
            timing.p90
        )
        print(message)
        XCTContext.runActivity(named: message) { _ in }
    }
}
