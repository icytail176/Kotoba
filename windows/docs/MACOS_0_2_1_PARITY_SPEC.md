# macOS 0.2.1 Build 3 product parity audit

Base: `714570930af974cfa9d0d6df65ad9e17eae7ca6a`. Current disk source, not old prompts, defines behavior. All Mac/shared reads are read-only.

## Initial feature audit

| Feature | Actual Mac contract | Windows at Phase 7 start |
| --- | --- | --- |
| Study/SRS/reinforcement/spelling/mastery/summary | Existing Phase 6 audited flow and atomic boundaries | ALREADY IMPLEMENTED |
| Romaji | JapaneseRomajiFormatter: NFC, kana mapping, explicit combinations, sokuon, syllabic n apostrophe, ordered long-vowel replacement | NOT IMPLEMENTED |
| Pitch | First authoritative `音调:` tag; circled 0–20, slash alternatives, plus compounds, comma alternatives; textual `[1+1, 3]`, not an accent diagram | NOT IMPLEMENTED |
| Loanword | Chinese-origin hidden even if partial/wasei; aliases normalized; unknown only visible if wasei | PARTIAL (detail present; study meaning qualifiers incomplete) |
| Filters | Book, search, JLPT, slash-token part of speech, exact tag, favorite, six status groups; archived excluded | PARTIAL (search/book only) |
| Sorting | Default expression/reading; recently studied descending/null last; meaningful due ascending/null last; lapse count descending; expression/reading/UUID ties | NOT IMPLEMENTED |
| Difficult | Persisted progress lapseCount >= 2, including suspended; not a wrong-answer heuristic | NOT IMPLEMENTED |
| Detail | Lexical/romaji/pitch/loanword, schedule/counters, favorite, history, reset, local conjugation | PARTIAL |
| History | Most recent 10, descending reviewedAt, rating and internal state/interval transitions; Mac UI does not display diagnostics | NOT IMPLEMENTED |
| Word reset | Create/reuse new progress, due/updated now, interval/review/lapse zero, lastReviewed nil; delete target logs; retain word updatedAt, ID/book/metadata/favorite/archive | NOT IMPLEMENTED |
| Forecast | Seven local days from today; learning/relearning/review; overdue clamped to today, new/suspended/archived excluded; read-only | NOT IMPLEMENTED |
| 7/30-day stats | Local day range incl today, excluding future days; formal logs, earliest-log newly learned words, manual/automatic mastery, rating distribution, persisted diagnostic first-pass, daily bars | NOT IMPLEMENTED |
| Lifetime stats | Distinct logged word IDs, all logs, streak ending today, top 10 Again review/relearning words excluding archived display records | NOT IMPLEMENTED |
| Kana | Hiragana/katakana switch; clear, voiced/semi-voiced and contracted tables; historic wi/we and particle notes; reference only, no speech | NOT IMPLEMENTED |
| Settings | New group 1–100/default10, review 1–200/default20, random fixed true, selected book, data I/O, attribution/about | PARTIAL (memory counts/local selected book only) |
| Keyboard help | Shared reference plus study secondary left/right paging; requested ? access | PARTIAL |
| CSV | UTF-8, eight export columns, sorted expression/reading, quotes/newlines; three required import fields, optional absent preserves updates, per-line errors, scoped duplicates, skip/update, explicit valid-row partial import | NOT IMPLEMENTED |
| CSV quality/editor preview | Normalized POS, local conjugation preview; critical/warning/info row quality and quality report CSV | NOT IMPLEMENTED |
| Backup | Mac JSON schema 3, ISO8601 dates, four entity arrays, merge(newer timestamp)/skip/overwrite ID, preflight final graph and atomic rollback | NOT IMPLEMENTED |
| Words/books CRUD | Word editor/create/delete confirmation; custom book create/edit/delete, builtin book protected; book relearn resets active progress but retains logs | NOT IMPLEMENTED |
| Home example | Random complete bilingual example, prefers literal target occurrence and highlights all matches | NOT IMPLEMENTED |
| Conjugation | Formal local rule engine, ambiguous generic POS does not guess; known orthographic exceptions; detail and revealed card secondary page | NOT IMPLEMENTED |
| Speech | No active speech service or speech controls in current source; SpeechTuningRecord exists only in frozen migration schema | NOT APPLICABLE |
| Cloud/auth/sync | Outside current local-first release and this phase | NOT APPLICABLE |

## Sources audited

- Services: JapaneseRomajiFormatter, PitchAccentPresentation, LoanwordEtymologyPresentation, PartOfSpeechTokenizer, ConjugationEngine/ConjugationRuleEngine, WordEditorPreviewService, ExampleHighlightingService, WordbookService, HomeDashboardService, StudyStatisticsCalculator/Service, AppSettings, AppAttribution, VocabularyCSVExportService, KotobaBackupService/Importer.
- Views/models: WordbookView/FilterBar/ViewModel, WordDetailView/Presentation, WordEditorView, WordBookManagementView/ViewModel, TodayStudyView/HomeDashboardViewModel, StudyCardView/StudyView, StatisticsView/ViewModel, KanaChartData/View, SettingsView/ViewModel, shared KeyboardShortcutReference and ConjugationFormsListView.
- Import: CSVParser, VocabularyCSVImportService, VocabularyImportQualityService and preview/target/result/view-model flows.
- Tests: LearningPolish, FinalFeatureUpdate, WordbookEnhancement/Filtering/Service, WordBookManagementLayout, UIFormattingAndLayout, HomeDashboard, StudyStatisticsCalculator, KanaChart, CSVParser/Import/Export, ImportQualityAndEditorPreview, SpellingAndConjugation, BuiltInConjugationAudit, KotobaBackupService/Importer and SettingsBackupImport.

## Implementation boundaries

Derived romaji/pitch/conjugation do not alter the manifest or canonical identity. Filtering/search/sorting/pagination and aggregates execute in Rust/SQLite; no full vocabulary/log transfer for frontend grouping. Extra history is bounded rather than Mac's unbounded show-all query. All destructive UI actions confirm; backend mutations transact and fail safely.

Schema 2 already represents required learning, history, custom lexical and book data. Versioned product settings use a separate app-data configuration file, not localStorage and not temporary study position. Native OS Unicode normalization and timezone APIs avoid a new formatter/normalization library. Only the official Tauri dialog dependency is added for system file selection; file parsing and writing remain Rust-side. [Official dialog API](https://v2.tauri.app/plugin/dialog/).

Mac Backup V3 relies on random local UUIDs and does not export canonical ID/key. Windows cannot safely identify all builtin duplicates across these graphs. Windows local backup therefore uses an explicit different format/version and validates canonical relationships against the embedded manifest and local graph. Mac files are rejected before mutation. CROSS-PLATFORM BACKUP remains NOT READY; an adapter would require trustworthy Mac canonical mapping first.

Final implementations, validation and remaining gaps are recorded in `windows/PHASE_7_REPORT.md`; the initial matrix above remains the starting audit, not a claim of completed features.
