# Kotoba Windows Phase 3 Report

验证日期：2026-10-05。PHASE 3 — Canonical Vocabulary Identity + Windows Built-in Vocabulary。

## Repository

- Branch: `feature/windows-client`
- Base HEAD: `ab7cb58a0fa819d08eef9b97ee6dda30d8324d3a` (Phase 2 final documentation; full Windows CI passed).
- Starting working tree: clean; no user changes overwritten.
- Implementation commit: pending — `Add canonical vocabulary manifest and Windows seed`.
- Final HEAD: implementation SHA will be recorded after commit; any report-finalization commit is documentation-only, pushed normally with full CI. A document cannot contain the hash of the commit containing itself; final branch tip is given in the final chat and by `git rev-parse HEAD`.
- No main merge, PR, tag or Release.

## Canonical Identity

- Strategy: checked-in immutable manifest + independent local UUID v4 records; stable canonical UUID v5 over fixed namespace and immutable key. Words use UTF-8 canonicalKey; books use UTF-8 `book:` + canonicalKey (documented domain separation).
- Namespace UUID: `01dfa402-05c2-46ab-a30f-acd35aa26ac0` — Kotoba Built-in Vocabulary Namespace v1.
- Manifest version: **1**; formatVersion **1**; sourceMacSeedVersion **8** is provenance only.
- Word keys: `jlpt:n5:000001` etc. Book keys: `jlpt-n5` through `jlpt-n1`.
- Initial frozen resource order allocated keys once. Keys are permanent entry identities, never recalculated from future CSV row number/order, expression, reading, meaning, normalization, or local UUID.
- Existing keys/IDs/provenance anchors cannot be reassigned. Removed identities remain reserved in `canonical_identity_ledger.json`; retired keys are explicit. Corrections retain identity; additions require new unused keys. No routine full-regeneration/update writer is provided.
- One-time bootstrap refuses to overwrite either manifest or ledger. Pristine replay is deterministic using the frozen namespace/createdAt. The ledger guards assignment; validator compares reservations with prior Git history, and hardcoded contract vectors guard UUID generation.

## Stable ID Status

CANONICAL ID SYSTEM: **READY**

WINDOWS MAPPING: **READY / IMPLEMENTED**

MACOS MAPPING: **NOT IMPLEMENTED**

The manifest provides shared identity; current Mac random VocabularyWord.id remains local and is not suddenly a cloud word_id.

## Manifest

- Path: `shared/vocabulary/canonical_vocabulary.json`.
- Schema: `shared/vocabulary/canonical_vocabulary.schema.json` (JSON Schema format 1).
- Permanent identity reservations: `shared/vocabulary/canonical_identity_ledger.json` (10,614 book/word identities).
- Documentation: `shared/vocabulary/README.md`.
- Total entries: **10,609**.

| Book | Count |
|---|---:|
| N5 | 802 |
| N4 | 755 |
| N3 | 1,817 |
| N2 | 3,206 |
| N1 | 4,029 |

Fields follow the actual read-only Mac seed pipeline: expression, reading, meaningChinese, partOfSpeech, exampleJapanese, exampleChinese, jlptLevel, ordered tags, nullable loanword source term/language and wasei/partial flags; book binding, canonical key/UUID and immutable initial provenance anchor. Book names/descriptions come from actual seed definitions. Metadata contains relative paths/hashes, counts, namespace, createdAt and independent versions; no user-machine absolute path.

All **836** current loanword sidecar rows match exactly one entry. Languages: eng 780, fre 22, ger 11, dut 9, por 6, ita 4, chi 2, lat 1, rus 1. The 2 Chinese-origin records are retained despite Mac presentation hiding them. This uses current seedVersion 8 data, not the old 46-row sample.

Pitch uses authoritative raw `音调:` tags on **10,398** entries; runtime Mac parsing is not reinterpreted. Romaji is runtime-derived by JapaneseRomajiFormatter, not persisted; no artificial romaji source field is added. Windows display parity is future work.

Validation: Python standard library checks schema subset + required lexical fields, fixed v1 counts, UUID formatting/v5, globally unique keys/IDs, known book bindings/levels, permanent ledger/anchor assignments, reserved identities, and source drift. Commands:

```sh
python3 windows/tools/vocabulary_manifest.py validate
python3 -m unittest discover -s windows/tools -p 'test_*.py'
```

Drift output explicitly reports added / removed / changed. Metadata correction is changed; expression/reading rename is removed + added requiring manual review. Logical reorder passes without identity changes. Source extraction code hash changes require review. Validation never writes/rebuilds IDs.

## Duplicate Audit

| Matching fields | Duplicate groups | Entries involved | Extra occurrences | Cross-book groups |
|---|---:|---:|---:|---:|
| expression | 72 | 150 | 78 | 48 |
| reading | 685 | 1,594 | 909 | 517 |
| expression + reading | 10 | 20 | 10 | 10 |
| Mac canonical-equivalent rule | 10 | 20 | 10 | 10 |

Equivalent matching mirrors the existing seed repair rule: trim, remove one leading `〜`, katakana-to-hiragana reading. No entries were merged or deduplicated; all 10,609 remain distinct identities. Intra-book exact/equivalent collisions are rejected as current Mac source validation requires.

## Windows SQLite

- Physical schema: **2**, `PRAGMA user_version = 2`.
- Historical `schema_1.sql` unchanged; real `schema_2.sql` migration extends existing tables transactionally.
- `word_books` / `vocabulary_words`: nullable canonical_id + canonical_key pair, partial UNIQUE indices for each, immutable identity triggers. Canonical books must be built-in; canonical words require a canonical built-in book.
- Built-ins require both canonical fields in importer/read semantics. Future custom rows may have both null. Local id is a separate UUID v4 and is preserved.
- `built_in_content`: singleton manifest_version, format_version, namespace_uuid, manifest_fingerprint, identity_fingerprint. Content version is independent of schema/SwiftData/Mac seed version. UUID v5 fingerprints are drift markers, not security signatures.
- Migration 1 → 2 preserves all four legacy entity rows, IDs, fields and relationships. Failed migration rolls back added columns/marker and retains old rows; unknown future schema still rejects safely.
- Production uses Tauri app_data_dir / kotoba.sqlite3. Mac Tauri development app data is separate from native SwiftData. No reset or deletion fallback.

## Import

Rust parses/validates the compiled manifest, then imports five books and 10,609 words in **one IMMEDIATE transaction**, reusing prepared statements. No Svelte JSON seeding or per-row transaction/open.

- Fresh import: PASS; exact five counts and total from actual SQLite.
- Close/reopen and second import: PASS; zero new books/words; local IDs unchanged.
- All local IDs, createdAt, favorite/archive flags, LearningProgress (state/due/interval/review/lapse counters), and ReviewLog preserved.
- Changed lexical metadata requires explicit new manifestVersion; updates lexical/source fields and updatedAt only when content changed. Same-version drift, namespace changes and downgrade reject without mutation.
- Missing entries are retained unchanged with flags/history, never hard-deleted or automatically unarchived. Synthetic v2 removal/correction tests exercise this ownership policy without publishing a real v2.
- Injected mid-import failure rolls back all partial built-ins/content marker while retaining existing custom word/book/progress/log.
- Benchmark-like native tempfile fresh-import measurement: **2.213 seconds** on macOS under the parallel test suite (10,609 words; single transaction). No fragile latency threshold; Windows measurement will be recorded from native CI output.
- No learning progress or review logs are created during seed. Windows SRS is not implemented.

## Windows Reads

Typed Rust services/IPC: list_builtin_word_books, get_word_book_summary, list_words, get_word by local UUID, search_words; internal canonical UUID lookup also available.

Pagination is limit **1..100**, unsigned offset, canonical ordering. Search is literal substring across expression/reading/Chinese meaning, maximum 200 characters; empty query returns empty. SQL is parameterized; percent/underscore/backslash are escaped for LIKE. Tests cover literal wildcard and SQL-injection-like text. No IPC sends the entire vocabulary.

Diagnostic UI displays Kotoba / Windows client prototype / Phase 3, Schema 2, manifest 1, total/per-book counts and first 20 search results with shortened canonical IDs. No sidebar/Home/study/formal Wordbook UI added.

## Tests

Local Rust tests: **40 passed, 0 failed, 0 ignored** (21 existing Phase 2 + 19 new Phase 3). Binary/doc targets have zero tests. Python tooling tests: **9 passed, 0 failed**.

New Rust coverage:

- Eight manifest/contract tests: embedded parse/counts/actual metadata; fixed UUID vectors; all book/word IDs/keys unique; lexical duplicates distinct; invalid identity/version/namespace/anchor; unknown book/missing field/count mismatch; correction/reorder stability; path-independent embedded parsing.
- Eleven SQLite/import/read tests: native tempfile schema/import/counts/close/reopen/second import; all local ID/user state preservation; new content lexical update; same-version drift/downgrade rejection; injected transaction rollback; canonical uniqueness/immutability/custom null; real four-entity Schema 1 → 2 preservation; migration failure rollback; pagination/summary/lookups; multilingual/escaped search; missing entry retention.
- All 21 Phase 2 migration/CRUD/encoding/FK/rollback/reopen tests retained. Historical fixtures create immutable Schema 1 explicitly where testing legacy rows.

Hardcoded vectors include:

| Key | UUID |
|---|---|
| book:jlpt-n5 | b4dcfc10-7e03-51a2-8f64-67d692c6a5ee |
| jlpt:n5:000001 | 6871898e-46e5-50c3-bf24-db1af7b30c46 |
| jlpt:n4:000001 | 465a5b4d-1a74-5b0a-b924-80a5cd2a193e |
| jlpt:n1:004029 | 74ee073b-38f3-5c4b-ba21-1279f7a659a2 |

RFC DNS UUID v5 vector is also checked. Python tests cover pristine bootstrap replay/refusal, real coverage, reorder, changed metadata, lexical rename/growth added/removed, invalid schema/identity and ledger anchors.

## macOS Validation

- npm run check (warnings fail): PASS, zero errors/warnings.
- npm run build: PASS.
- cargo fmt --check / cargo check --locked / cargo clippy --locked --all-targets -- -D warnings: PASS.
- cargo test --locked: PASS, 40 tests.
- tauri dev: PASS. Native diagnostic window showed Schema 2, manifest 1, total 10,609, N5 802 / N4 755 / N3 1,817 / N2 3,206 / N1 4,029; Japanese rendered correctly. Query `高校` returned 2 correct entries; Chinese `高中` returned 4. App quit normally.
- Actual compiled executable `--verify-embedded-manifest` from an empty temporary cwd: PASS, manifest 1 / total 10,609 / five counts. No production database opened by this probe.
- Existing npm audit: 3 low-severity transitive development findings unchanged; no npm dependency added. Existing uuid crate enables v5, adding its locked sha1_smol transitive implementation; no new direct dependency.

## Windows CI

Pending implementation push. All existing npm ci/check/build, Rust fmt/check/clippy/test and Tauri Windows build gates remain enabled. Added manifest validation/tool tests and actual release EXE embedded-resource probe from empty temp cwd. Native test uses tempfile SQLite, real migration 2, exact full import, close/reopen and second-import identity preservation. No continue-on-error or skip.

## macOS Project Isolation

**NO SOURCE MODIFICATION**.

Allowed change scope: windows/**, shared/vocabulary/**, .github/workflows/windows-build.yml. No edits to Kotoba/**, KotobaTests/**, Kotoba.xcodeproj/**, existing resources or old Scripts. Mac seedVersion remains 8; active SwiftData remains V3. No native user store read or changed. Historical Windows schema_1.sql is unchanged.

## Future macOS Integration

**RECOMMENDED: V4**, design only. Add nullable canonicalID to VocabularyWord and WordBook; preserve all local word/book/progress/log UUIDs, relationships, favorites, archive state and history.

Before mutation, prepare an exact read-only plan by known built-in book and manifest expression/reading; approved normalization/alias matching must be uniquely resolvable. Ambiguous/edited/unmatched rows remain untouched with nil canonicalID and explicit diagnostics/manual safe fallback. Do not guess, rewrite local IDs or collapse legacy history. Duplicate legacy records need a separate alias/owner policy before uniqueness/sync. Diagnostic localID → canonicalID aliases may preserve references; future cloud built-in IDs use canonical IDs.

## Limitations

Mac canonical mapping not implemented; no V4 runtime migration. Windows SRS, romaji/pitch display parity, sync/auth/cloud/backup conversion and formal product UI are not implemented. Physical Windows application/installer UI runtime not tested; native MSVC automated import and release packaging are separate evidence. Windows signing not configured. Fingerprints/ledger are review guards, not cryptographic package authenticity. Future aliases, edited/ambiguous legacy records, custom-word identity, archive/tombstone and cross-device progress/log conflicts require further design.

## Phase 3 Result

**PENDING WINDOWS CI** — local validation passes; final result will be recorded after the complete native run.
