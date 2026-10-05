# Kotoba Canonical Vocabulary — Manifest v1

CANONICAL ID SYSTEM: **READY**
WINDOWS CANONICAL MAPPING: **IMPLEMENTED**
MACOS CANONICAL MAPPING: **NOT IMPLEMENTED**

Namespace: `01dfa402-05c2-46ab-a30f-acd35aa26ac0` (Kotoba Built-in Vocabulary Namespace v1).

`canonical_vocabulary.json` is the checked-in source of truth for built-in lexical identity. `canonical_vocabulary.schema.json` defines format 1; `canonical_identity_ledger.json` reserves every released key/UUID/original provenance anchor, including identities later retired. These files contain no user-machine paths.

## Dual identity and permanent rules

Local record ID and canonical ID are different concepts. Mac keeps its existing random UUIDs. Windows allocates independent local UUID v4 records and stores separate canonical UUIDs. Canonical IDs come **only** from the checked-in manifest:

- word: UUID v5(namespace, UTF-8 canonicalKey)
- book: UUID v5(namespace, UTF-8 `book:` + canonicalKey)

Keys start as `jlpt:n5:000001` etc.; books are `jlpt-n5` through `jlpt-n1`. The initial lexical snapshot order helped allocate keys exactly once. **These keys are permanent manifest identities, not CSV row indices.** Future resource/manifest reordering never renumbers them. Expression, reading, meaning, local UUID and mutable metadata never calculate permanent identity.

Existing canonical IDs are immutable. Existing canonical keys must never be reassigned. Removed entries keep historical identity reserved. New entries receive new canonical keys. Metadata corrections do not change identity. Upstream reorder does not change identity. Never regenerate the manifest from scratch after public sync identity is in use.

`identityAnchor` is a frozen SHA-256 provenance/integrity token over the initial book/expression/reading/occurrence snapshot. It is **not** the UUID input or a future lexical matching algorithm. Corrections retain it. The ledger guards key/ID/anchor assignments; validation also compares all existing reservations to the prior Git commit. Neither validator nor importer performs fuzzy rematching or deduplication.

## Bootstrap and deterministic tooling

Python 3.9+ standard library only:

```sh
python3 windows/tools/vocabulary_manifest.py validate
python3 -m unittest discover -s windows/tools -p 'test_*.py'
```

The one-time `bootstrap` command refuses to overwrite an existing manifest **or ledger**. Its namespace and original createdAt are now frozen constants so a disposable pristine snapshot can be replayed deterministically for auditing. This is not a routine update command. Never delete checked-in identity files to bypass the guard.

For maintenance, edit approved lexical metadata in place while keeping canonicalKey/canonicalId/identityAnchor, bump manifestVersion, validate current sources, and review the diff. For additions, allocate a new unused key and append its permanent reservation; do not renumber existing entries. For removals, retain the ledger reservation and list the key in retiredKeys. No automatic maintenance writer is implemented in Phase 3. A namespace/format change requires a separate design, never reusing v1 keys with different IDs.

CI fetches the parent commit and rejects deletion/reassignment of existing ledger reservations. Bootstrap's first commit has no prior ledger. Fixed UUID contract vectors separately guard namespace/generator changes. JSON Schema validation uses a small documented subset validator (type, required, additionalProperties, const, enum, pattern, minimum/minLength and items), plus semantic checks; no external JSON Schema package is needed.

## Actual snapshot and metadata provenance

Mac `BuiltInWordBookService` version 8 defines five books:

| Book | Count |
|---|---:|
| N5 | 802 |
| N4 | 755 |
| N3 | 1,817 |
| N2 | 3,206 |
| N1 | 4,029 |
| Total | 10,609 |

Read-only source CSVs: `Kotoba/Resources/eggrolls_kotoba_N*_strict.csv`. Fields: expression, reading, meaningChinese, partOfSpeech, exampleJapanese, exampleChinese, jlptLevel, tags. Extraction trims fields, normalizes POS by ordered unique `/` tokens, and tags by ordered unique `;` tokens, matching current `PartOfSpeechTokenizer` / seed parsing. Five book names and descriptions use the actual seed definitions. No rows were deduplicated or invented.

`builtin_loanword_etymology.csv` is matched using the seed's level + NFKC expression + NFKC/hiragana reading rule. All **836** sidecar rows match exactly one current entry. Language counts: eng 780, fre 22, ger 11, dut 9, por 6, ita 4, chi 2, lat 1, rus 1. Nullable source term/code and wasei/partial booleans are preserved. The **2 Chinese-origin records remain in source data**; hiding them is a presentation policy, not data deletion. This is the current pipeline, not the old 46-record sample.

Pitch accent is authoritative raw `音调:` tags (10,398 entries); `PitchAccentPresentation` derives display alternatives/components at runtime. The manifest retains tags without reinterpretation. Romaji is derived at runtime by `JapaneseRomajiFormatter` and is not persisted in VocabularyWord; no romaji field is added. Windows romaji/pitch display parity can be implemented later against these sources.

`generatedFrom` records relative source paths/SHA-256 snapshot hashes over canonical LF text (Windows CRLF checkout does not change provenance) and sourceMacSeedVersion 8. This seed version is provenance; shared manifestVersion 1 and Windows physical schema 2 are independent versions.

## Duplicate audit (preserved, never merged)

| Key | Duplicate groups | Entries involved | Extra occurrences | Cross-book groups |
|---|---:|---:|---:|---:|
| expression | 72 | 150 | 78 | 48 |
| reading | 685 | 1,594 | 909 | 517 |
| expression + reading | 10 | 20 | 10 | 10 |
| Mac canonical-equivalent matching | 10 | 20 | 10 | 10 |

Canonical-equivalent means trim, removal of one leading `〜`, and katakana→hiragana reading conversion exactly as current seed repair. Per-book exact/equivalent duplicates are rejected by the current Mac source validation. Cross-book duplicates retain distinct keys/IDs: each manifest entry has its own permanent identity even when its lexical fields match another book.

## Drift detection

Validation compares the manifest's seeded lexical fields with current source pipeline output. It reports **added / removed / changed**, without writing files. Metadata changes under the same book/expression/reading key are changed; expression/reading changes may report removed + added and require manual review, never guessed as an identity move. Source row order/CSV quoting changes with identical logical content pass. Pipeline source hashes changing require explicit extraction-semantics review, even if current data happens to match.

Counts are the audited v1 baseline, not arbitrary adjustable test constants. Intentional new content versions require reviewed count/ledger changes. None of the existing Mac resource files or generator scripts are modified.

## Windows packaging and import

Rust `include_str!` embeds both manifest and ledger into the executable; no runtime repository-relative path is used and no JSON travels through Svelte for import. Tauri setup opens/migrates Schema 2, validates the embedded manifest, imports in one transaction with prepared statements, then registers read-only diagnostics.

CI also runs the **actual release EXE** with `--verify-embedded-manifest` from an empty temporary working directory. This read-only probe verifies format/identities/counts without starting Tauri or opening user databases, proving packaging independently of repository paths. Native Windows tests separately perform temporary file SQLite migration/import/counts/close/reopen/idempotency.

Importer ownership: lexical content, book assignment, source tags and loanword metadata. It retains local IDs, createdAt, favorites, archive flags, LearningProgress and ReviewLog. Unchanged lexical rows do not change updatedAt. Missing prior canonical entries remain untouched, including flags/history; no hard deletion or automatic unarchive. New entries get fresh local UUIDs. No learning progress or review logs are seeded in Phase 3.

`built_in_content` records manifestVersion/formatVersion/namespace plus content/identity fingerprints; PRAGMA user_version remains physical schema version. Fingerprints use UUID v5 over deterministic serialized content/identity data for drift detection, not security signatures. Unversioned content changes, namespace switches and content downgrades are rejected without mutation.

## Future macOS integration (design only)

**RECOMMENDED: SwiftData V4** with nullable canonicalID on VocabularyWord and WordBook, preserving every existing local UUID and relationship. No V4 or Mac runtime mapping is implemented here.

Prepare a complete read-only migration plan first: select known built-in book → match exact manifest book/expression/reading → use approved normalization/alias rules only when uniquely resolvable. Preserve local word/progress/log IDs, favorites, archive state and history. Ambiguous, edited or unmatched records remain unchanged with canonicalID nil and an explicit diagnostic/manual safe fallback; do not guess or rewrite local IDs. Historical approved lexical aliases may be needed after expression/reading corrections; source provenance hashes alone are not enough to resolve such edits.

Duplicate legacy local records require a separate alias/owner policy before uniqueness constraints or sync. A localID→canonicalID diagnostic mapping can retain legacy references, but cloud built-in identity uses canonical IDs, not random Mac UUIDs. Matching helpers are migration aids, never the permanent identity algorithm. Account/progress/log/favorite sync ownership and conflict resolution remain out of scope.
