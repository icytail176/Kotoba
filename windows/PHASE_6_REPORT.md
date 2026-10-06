# Kotoba Windows Phase 6 Report

## Recovery

The previous two transport interruptions were treated as chat failures, not evidence of an empty working tree. Existing uncommitted Rust study/repository/IPC code, Svelte session components, controller, spelling and keyboard code were found and retained. No Phase 6 implementation commit existed. No reset, clean, stash, discard checkout, rebase or duplicate implementation was performed.

Recovery classification before continuation: COMPLETE — Phase 5 scheduler/mutation foundation and lexical model; PARTIAL — Phase 6 study queue, IPC, session/controller, reinforcement, spelling, keyboard/IME and UI; NOT STARTED — complete Phase 6 coverage, parity specification, final manual audit, report and commit/CI verification. Continuation completed these gaps and repaired actual source-parity discrepancies, including error-type serialization and Foundation spelling normalization.

## Repository

- Branch: `feature/windows-client`.
- Starting HEAD: `a0f640a3d87087da8154e45f53378cd879ea4bac`.
- Implementation commit: `110b9229fdb220f93b408f91c137547335d2ed5c` — Implement Windows study session and spelling flow.
- Final implementation HEAD: `110b9229fdb220f93b408f91c137547335d2ed5c` (no CI source repair was needed).
- A subsequent report-only commit records the verified results below; it does not change the implementation. Normal push is used and CI remains enabled.
- Changes are restricted to `windows/**`; workflow, dependencies, locks, canonical vocabulary and Schema 2 remain unchanged.

## macOS StudySession Audit

Current Mac source and tests were read only; they override any conflicting prompt assumptions. Audited files and exact contracts are recorded in [STUDY_SESSION_PARITY_SPEC.md](docs/STUDY_SESSION_PARITY_SPEC.md): StudySession/StudyQueue/SpellingQuestion services, study and spelling view models, flow states, study/card/spelling/summary views, Today Study and Home models, keyboard reference and corresponding tests. Phase 5 report and SRS parity specification were also reviewed.

L and R start separate new-only and due-only groups. Missing progress is logically new; archived/suspended words are excluded. Learning/relearning is minute-due; review includes the current local day. Typed memory-only phases distinguish formal, reinforcement, expression spelling, reading spelling, summary and terminal/error/loading states. Formal persistence precedes memory advancement; temporary session position is not saved.

The host timezone provider uses Core Foundation on Mac and native dynamic/year-specific Win32 timezone APIs on Windows. No hard-coded timezone or silent UTC fallback is used. Queue and formal scheduling remain Rust-authoritative. Windows-specific tests cover Pacific spring/fall DST, Lord Howe half-hour DST and UTC without changing system settings.

## Session Flow

Today Study → reveal/formal rating → appended Again reinforcement → all expression questions/retries → Han reading questions/retries → diagnostic enrichment → summary → exactly-once completion. Empty/error/cancelled states are explicit. The page is composed from TodayStudy, StudyCard, SpellingCard, StudySummary, StudyDialog and HomeSearch with typed controller, spelling, keyboard and IPC modules.

## Formal Study

Reveal gates all ratings. Again/Hard/Good/Manual Mastered call the existing authoritative Phase 5 atomic service using the expected snapshot and original prepared clock. Each successful formal rating creates exactly one log. Pending blocks duplicate ratings, favorite and exit. Save failure keeps the card and allows retry; stale progress invalidates the group with a safe restart message.

Automatic mastery remains one Good log, and removes later reinforcement/spelling candidates. Manual Mastered is one Easy log with suspended/interval-zero progress. Existing scheduler, mastery thresholds, calendar behavior and 60-day caps are preserved.

## Favorite

F uses an atomic expected-boolean mutation. UI changes only after success; failure retains the prior display. Favorite changes neither scheduler/progress nor logs/session position. Persistence and SQL-failure rollback are tested; the native audit reopened the favorite on 先 successfully.

## Reinforcement

Again appends another session appearance; Hard and Good advance. These three actions have no scheduler, progress, timestamp or log mutation. Mastered prepares an override, persists suspended/interval-zero/due-now atomically, then updates session memory and removes candidates. It retains formal review/lapse counters, lastReviewedAt and the original log/rating. Rollback/retry tests prove failure does not fabricate mastery or advance.

## Spelling Round 1

Chinese meaning/context prompts expression, including kana-only words. Literal expression occurrences in example context are masked. Wrong answers stay unlocked, increment actual wrong counts and retain the raw last wrong answer. Correct feedback locks; the next Return advances. A wrong or hinted appearance appends exactly one retry when corrected. Clean first appearance and clean requeued pass are distinct per-word results.

Cmd-Shift-H on Mac / Ctrl-Shift-H on Windows shows the complete reading only in round 1, forces non-first-pass/requeue, and is blocked while composing/locked/pending/already hinted. No first-character hint is invented.

## Spelling Round 2

Only current Mac Han ranges qualify; kana, Latin and 〇 do not. Expression prompts reading; no hint or romaji/fuzzy acceptance. Wrong/correct/requeue behavior matches round 1.

Normalization was verified against 60 golden results generated by compiling the actual unmodified Swift checker with a temporary model stub. The Windows checker preserves current Foundation edge behavior: U+200B trims, U+FEFF remains, and halfwidth voiced marks can remain decomposed and fail Mac's kana-only scalar guard. Ordinary fullwidth katakana and canonical equivalence follow Mac. See the specification and `tests/fixtures/mac-spelling-golden.json`.

## IME

Standard compositionstart/compositionend, KeyboardEvent.isComposing, keyCode 229 and an event-turn ending guard protect the dispatcher. Compositionend never submits. While marked, Enter/Escape/Space/1/2/3/Delete/Backspace/F are left to the IME.

Actual macOS Japanese Romaji IME was used in the native Tauri WKWebView: physical k/a/n/a produced marked かな, Space converted candidates, Escape cancelled conversion without exiting, and rating/delete/favorite keys caused no study mutation. Physical s/a/k/i and conversion produced marked 先. Candidate confirmation and composition completion did not submit; a subsequent normal Return submitted. Hint was unavailable while composing. This is Mac WebKit validation only.

Physical Windows interactive runtime: **NOT TESTED**. Microsoft IME physical Windows test: **NOT TESTED**.

## Keyboard

One study dispatcher and one Today Study window listener share the help mappings. Command/Control selection is centralized. Home L/R, primary-F, search arrows/Enter/Escape; cards Space/1/2/3/Delete/Backspace/F/Escape; spelling Enter/primary-Shift-H/Escape; summary Enter. Repeat, editable context, native dialog, pending and IME guards are tested. Native search focus, arrow selection, detail opening/closing and help-dialog shortcut suppression were audited.

## Summary

Summary uses unique formal outcomes, original ratings with mastery overrides, new/lapse counts, per-word reinforcement retry counts and both spelling rounds' first-pass/retry/hint counts. Completion is guarded once across Return/repeat/button races. Active Escape confirms; continuing retains input/question, exiting retains all committed history.

## Persistence

Formal ratings insert one log each. Reinforcement/spelling insert none. Spelling atomically enriches the session's original formal log IDs: raw last wrong answer/expected/direction, spelling/reading counts and error-type union. It preserves repeatedWrongCount, rating, scheduler transition, formal clock, progress and timestamps. Multirow rollback, invalid requests, retry/idempotence and preserving older history are tested. Diagnostic-save failure permits retry or continuing with in-memory summary after formal progress has already committed, matching Mac.

A tempfile fake-word integration combines formal ratings, automatic/manual mastery, reinforcement override, favorite, enrichment and close/reopen checks. Another tempfile imports the actual 10,609 manifest and returns a bounded lexical N5 sample without eagerly creating progress rows.

## Tests

All pre-existing tests remain. Phase 6 adds 14 cross-platform Rust tests and two Windows-only native timezone tests, plus 30 frontend tests (including 60 Swift-generated normalization vectors).

| Local gate | Result |
| --- | --- |
| `npm run check -- --fail-on-warnings` | PASS: 0 errors, 0 warnings |
| `npm run test:ui` | PASS: 37 passed, 0 failed |
| `npm run build` | PASS |
| `cargo fmt --check` | PASS |
| `cargo check --locked` | PASS |
| `cargo clippy --locked --all-targets -- -D warnings` | PASS |
| `cargo test --locked` | PASS: 78 passed, 0 failed on Mac |
| Manifest validation/drift | PASS: 10,609; N5 802, N4 755, N3 1,817, N2 3,206, N1 4,029 |
| Python tooling | PASS: 11 passed, 0 failed |

## macOS Tauri Audit

`npm run tauri dev` ran against debug-only isolated `KOTOBA_TEST_APP_DATA=/private/tmp/kotoba-phase6-runtime-20261006`, never the long-lived development database. The current debug executable was used, not an older generated app bundle.

- Four-word group: 先 Again + favorite; 痛い Hard; 楽しい Good; どうか Manual Mastered. Reinforcement Again/Hard caused no new logs. Round 1 used wrong answer, hint and a clean requeue; round 2 rejected romaji `itai`, accepted イタイ and completed its requeue. Summary: four unique words, one of each rating; each spelling round 3 eligible / 2 first-pass / 1 retry-pass; round-one hint count 1.
- Due-only group: 先 formal Again, reinforcement Mastered. Summary excluded spelling; original Again logs and reviewCount 2 survived the override.
- Exit group: 外国 formal Again/reinforcement Good, then spelling Escape confirmation. Continue retained the question; dialog keys did not rate/favorite; confirmed exit retained the formal log.
- Actual SQLite write-lock failure: たまに Good could not save, showed a safe retry, stayed on card and inserted no progress/log. Additional rating and Escape during pending had no effect. After lock release, retry saved the original Good exactly once and completed kana-only expression spelling without a reading round.
- Read-only reopened DB: Schema 2; 10,609 words, six progress rows, **seven formal ratings = seven logs**; favorite persisted; two mastered words; expected diagnostics and original formal ratings preserved. No reinforcement or spelling logs.
- Observed layouts: 720×560, 900×700, 1200×800 and 1405×900 (desktop-constrained practical maximum when attempting 1440×900). Home/card/spelling/summary/dialog states were inspected across these sizes. No observed horizontal overflow; scrollable content and footer actions remained usable. Exact 1440×900 was not achieved and is not claimed.
- Actual Japanese IME audit: PASS for the observed composition/conversion sequence above. Native automatic-mastery threshold and injected stale/enrichment failures are covered by deterministic tests rather than artificial changes to the audit database.

## Windows CI

Implementation CI: **completed / success** on 2026-10-06; run **37403092828**, [GitHub run](https://github.com/icytail176/Kotoba/actions/runs/37403092828), head `110b9229fdb220f93b408f91c137547335d2ed5c`. The Windows MSVC job completed in 11m48s. Actual downloaded run metadata and logs were checked against the exact implementation SHA and all required successful steps.

All gates passed: npm ci, Svelte check (0 errors/warnings), frontend tests (37 passed / 0 failed), frontend build, manifest validation (10,609/no drift), Python tooling (11 passed), cargo fmt, cargo check, cargo clippy with warnings denied, cargo test (**80 passed / 0 failed**, including **16 Phase 6 study/native-timezone tests**), Tauri Windows build, release embedded-manifest probe outside the repository, output verification and artifact upload.

Generated nonempty outputs: EXE 15,998,464 bytes; MSI 5,345,280 bytes; NSIS installer 3,437,498 bytes. Artifact `kotoba-windows-phase1` successfully uploaded (existing workflow artifact name), ID 11386502316. This certifies the Windows native build/tests and release resource probe, not a physical interactive Windows/IME audit.

## Parity

MAC/WINDOWS STUDY FLOW PARITY: **READY**, within the explicitly documented Phase 6 flow scope and physical-runtime limitations.

## macOS Isolation

**NO SOURCE MODIFICATION**. No Kotoba, KotobaTests, Xcode, Mac resources, SwiftData, backup, seed or shared canonical identity edits. No dependencies or schema migration were added.

## Known Limitations

Physical Windows runtime and Microsoft IME are not tested; Windows signing is not configured. Statistics, forecast, sync, auth, CSV, backup and settings expansion are outside Phase 6. Romaji/pitch/conjugation-page presentation, secondary arrow paging and speech remain pending product parity. Random sequence and exact Mac localized summary collation are not guaranteed. Native timezone tests do not certify every historical/non-Gregorian rule.

## Phase 6 Result

**PASS**. Existing partial work was recovered/reused; full local gates and implementation Windows CI passed; the native Mac session/Japanese IME audits passed for the observed flows. Physical Windows runtime and Microsoft IME remain **NOT TESTED**.
