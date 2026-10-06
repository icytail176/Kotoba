# Kotoba Windows Client

Status: Phase 6 — Today Study, atomic formal ratings, reinforcement, two-stage spelling and keyboard/IME safety.

Technology: Tauri 2, Svelte 5, TypeScript and Rust. SvelteKit uses the static adapter and Vite. No new dependencies are introduced for Phase 6.

## Product UI

The Simplified Chinese sidebar contains 今日学习、单词管理、词书、学习统计、五十音图、设置. Today Study, vocabulary browsing, wordbooks and word details are implemented; statistics, kana chart and settings remain explicitly marked for a later phase.

Browse all 10,609 built-in words or one of five JLPT books, 50 words per page. Search expression, reading or Chinese meaning through SQLite, with a 250 ms debounce and stale-response protection. Clearing search returns to initial browsing. Details show existing lexical content and optional examples, tags and permitted loanword sources. Chinese-origin source metadata remains stored but hidden in the UI, matching the current Mac presentation policy.

The native window starts at 1100 × 760, with a 720 × 560 minimum. Wide windows display list and detail together; narrow windows replace the list with detail. CSS semantic tokens follow the system light/dark preference, and system fonts provide Japanese fallback. Buttons support keyboard focus, Enter activation and Escape detail/back navigation.

## Development on macOS

Prerequisites: Node.js/npm, Rust/Cargo and Xcode command line tools. Node 26 is used by CI and the dependency-free frontend state tests.

```sh
cd windows
npm ci
npm run tauri dev
```

Running `tauri dev` on macOS verifies the shared application stack and macOS WebView layout. Physical Windows UI runtime remains **NOT TESTED**. Windows CI validates native Rust tests and EXE/MSI/NSIS builds; signing is not configured.

## Validation

```sh
npm run check -- --fail-on-warnings
npm run test:ui
npm run build
python3 tools/vocabulary_manifest.py validate
python3 -m unittest discover -s tools -p 'test_*.py'
cd src-tauri
cargo fmt --check
cargo check --locked
cargo clippy --locked --all-targets -- -D warnings
cargo test --locked
```

Lockfiles retain reproducible dependency resolution. Generated output and local dependencies are ignored. Frontend state tests use Node's built-in test runner and TypeScript stripping, without an added test framework.

## Data and services

SQLite Schema 2 is initialized through Rust in the Tauri OS app-data directory as `kotoba.sqlite3`. The canonical manifest is embedded at compile time; transactional, idempotent import preserves user state. Schema, seed version, canonical identities and shared resources are unchanged by Phase 4.

`src/lib/services/vocabulary.ts` centralizes typed IPC. Product-facing `browse_books`, `browse_words`, `browse_search` and `word_detail` use dedicated camelCase DTOs. IDs remain internal references for reads and are not displayed. Bounded list/search queries join book labels directly, with one count and one page query. Missing detail returns `null`; transient errors show safe Chinese messages and retry. Internal `database_info` diagnostics remain available but are absent from the product UI. Phase 3 database read methods and their contracts/tests remain intact.

Canonical identity is **READY** and Windows mapping is **IMPLEMENTED**; Mac mapping is **NOT IMPLEMENTED**. See [shared identity rules](../shared/vocabulary/README.md), [the data contract](docs/CROSS_PLATFORM_DATA_CONTRACT.md), [Phase 3 report](PHASE_3_REPORT.md) and [Phase 4 report](PHASE_4_REPORT.md).

Phase 5 supplies the pure scheduler and atomic review/mastery service. Phase 6 adds typed study IPC, native OS timezone providers, a session controller, separate L/new and R/review entry points, session-only reinforcement, two-stage spelling, favorite persistence, original-log enrichment and an exactly-once summary. Schema remains 2 and all earlier tests are retained. See [SRS parity](docs/SRS_PARITY_SPEC.md), [study parity](docs/STUDY_SESSION_PARITY_SPEC.md) and [Phase 6 report](PHASE_6_REPORT.md).

For mutation audits, development builds accept an explicit absolute `KOTOBA_TEST_APP_DATA` directory; release builds always use normal app data:

```sh
KOTOBA_TEST_APP_DATA=/private/tmp/kotoba-study-audit npm run tauri dev
```

Phase 6 does not add statistics, sync, auth, CSV, backup or vocabulary editing/reset. Pitch, romaji, speech and conjugation presentation parity remain pending. Existing macOS source, tests, project files, shared vocabulary and lockfiles are unchanged.
