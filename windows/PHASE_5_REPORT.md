# Kotoba Windows Phase 5 Report

验证日期：2026-10-05。PHASE 5 — SRS Scheduler + LearningProgress + Automatic Mastery。

## Repository

- Branch: `feature/windows-client`.
- Base HEAD: `924c4ef83e5422857f652655fd3f323270b09bf6`; starting working tree clean and synchronized.
- Implementation commit: pending — `Add Windows SRS scheduler and review persistence`.
- Final HEAD: pending CI/report finalization. Final branch tip will be given in the final chat; a document cannot include the hash of the commit containing itself.
- No main merge, PR, tag, Release or Supabase work.

## macOS Scheduler Audit

Read-only audit covered DefaultReviewScheduler/ReviewScheduler/ReviewScheduleResult/AppSettings, AutoMasteryPolicy, LearningState/ReviewRating/LearningProgress/ReviewLog, StudySessionViewModel, StudyQueueService, BuiltInWordBookService, WordbookService, and scheduler/automatic-mastery/session/queue/reset tests. Current source context: base commit above, Mac 0.2.1 build 3. Full audit, source list and semantics are in [SRS_PARITY_SPEC.md](docs/SRS_PARITY_SPEC.md).

- Persisted states: new, learning, relearning, review, suspended.
- Formal raw ratings: again, hard, good, easy. Current easy means manual Mastered, not the root AGENTS.md's historical easy interval multiplication.
- Time: explicit now; local Calendar day addition, preserving wall time across DST. Minute schedules use precise ten-minute duration. Stored dates remain UTC microseconds INTEGER.
- Counters: every active formal rating increments reviewCount once. Review/relearning Again increments lapseCount; new/learning Again does not. Mastery increments reviews and preserves lapses.
- Prompt reference difference: review eligibility is by local calendar day, including later-today review due times; minute-state eligibility is exact dueAt <= now. The source is followed rather than a uniform exact cutoff.
- Mac creates new progress eagerly with vocabulary. Windows keeps missing progress logically new and creates/stores progress inside the first successful formal-rating transaction, without bulk creating 10,609 records.
- Archived words are excluded by Mac queues; Windows also rejects archived/stale submissions inside the atomic service. Suspended pure scheduling is a no-op as on Mac; the formal service rejects a suspended submission.

## Transition Table

r/l are previous review/lapse counts. D(n) is local civil-calendar day addition; M(10) is a precise ten minutes. Day intervals clamp to 1–60.

| State | Rating | Next state | Interval | Due | Reviews | Lapses |
|---|---|---|---:|---|---:|---:|
| new / learning | again | learning | 0 | M(10) | r+1 | l |
| new / learning | hard | review | 1 | D(1) | r+1 | l |
| new / learning | good | review | 2 | D(2) | r+1 | l |
| relearning | again | relearning | 0 | M(10) | r+1 | l+1 |
| relearning | hard | review | 1 | D(1) | r+1 | l |
| relearning | good | review | 2 | D(2) | r+1 | l |
| review | again | relearning | 0 | M(10) | r+1 | l+1 |
| review | hard | review | ceil(i×1.2), capped | D(interval) | r+1 | l |
| review | good, not auto | review | ceil(i×2), capped | D(interval) | r+1 | l |
| any active | easy / manual Mastered | suspended | 0 | now | r+1 | l |
| qualifying review | good / automatic mastery | suspended | 0 | now | r+1 | l |
| suspended, pure core only | any | suspended | previous interval | now | r | l |

Negative progress, unknown enum raw values, counter/date overflow and missing calendar coverage return typed errors. No panic/unwrap or implicit timezone fallback. Pure core consumes a lightweight ProgressSnapshot without row identity or database operations.

## Automatic Mastery

Exact qualification uses **pre-state review + pre-interval 60 + active/non-archived + previous formal Good + current formal Good**. No invented extra qualification; due queue semantics belong to the future session and are exposed as a matching read API.

- 32 → Good → 60 does not immediately master.
- Hard at 60 breaks qualification. First subsequent Good stays review/60; second Good masters.
- Again enters relearning and increments lapse. Repeated Again increments lapse again; relearning Good returns to review/2 and cannot directly master.
- One successful automatic mastery transaction adds exactly one **good** log: previous review/60 → suspended/0, due now. No second fake log or easy substitution.
- Real transaction integration walks 2/4/8/16/32/60 and then masters, persists seven formal logs, closes and reopens the database with identical state/history.
- Injected insert failure during qualification leaves progress/log unchanged; retrying the same snapshot commits exactly one Good log.

## Persistence

- `BEGIN IMMEDIATE` transaction: active word check → one progress lookup → expected-snapshot comparison → indexed previous-formal-log lookup → pure schedule → progress upsert → one log insertion → word timestamp update → commit.
- Returned CommittedReview is published only after commit succeeds. No in-memory session/UI commit before persistence.
- First rating atomically creates local UUID v4 progress. Every formal log has a local UUID v4 and references the Windows local word ID. Existing progress ID/createdAt are retained.
- Progress stores state, due, interval, review/lapse counters, lastReviewedAt and updatedAt. Logs store actual rating, previous/next states/intervals, reviewedAt and scheduledDueAt; Again adds meaning error. Spelling fields remain null/zero.
- Source spelling enriches existing formal logs; reinforcement creates no logs. Latest-formal lookup therefore includes enriched rows and never filters by empty spelling columns.
- Latest/recent lookup: per-word `ORDER BY reviewed_at DESC,id LIMIT ...`; index use is asserted with EXPLAIN QUERY PLAN. Recent history returns a dedicated camelCase FormalLogDto, bounded 1–100 (caller may request 10).
- Exact expected-progress snapshot makes repeated callbacks detectable as StaleProgress; successful first commit prevents a duplicate with the old snapshot. A failed transaction can retry the original snapshot. Phase 6 session guards remain separate future integration, without a network idempotency token.
- Rollback tests cover checkpoints after progress and after log; actual SQL progress/log/word update failures; and an actual deferred foreign-key **commit failure**. They assert progress, log count/content and relevant word state are unchanged, including absent-progress rollback.
- Reset behavior was audited and documented but no reset API/UI was added.

## SQLite

- Schema version: **2**. Migration: **NONE**.
- Existing fields already support all formal progress/log semantics. No identity/schema/seed/backup changes.
- Existing `logs_by_word_date(word_id, reviewed_at DESC, id)` supports bounded latest/recent queries; existing unique word progress and due indices remain. No new index or premature schema revision.
- New eligible service: non-archived missing/new progress, bounded pages and optional book scope. New due service: active minute states with exact cutoff; review before next local day start. New/suspended/archived excluded.
- Formal rating never scans all logs or vocabulary. No N+1 queries. Detail adds progress state through one LEFT JOIN, exposing only the presentation group.

## Architecture

- `srs/models.rs`: typed domain errors, formal input wrapper, pure ProgressSnapshot/result, presentation enum and log DTO.
- `srs/calendar.rs`: explicit complete timezone offset-rule context, checked civil-day arithmetic, DST gap/fold resolution, local day-end cutoff. No dependency added and no implicit host timezone.
- `srs/scheduler.rs`: pure transition/rounding/cap/automatic-mastery core with injected now/context; no SQLite calls or system-clock reads.
- `srs/service.rs`: transaction orchestration and read services; expected snapshot/active/suspended guards; committed result returned after persistence.
- `db/srs_repository.rs`: SQL and transaction boundary, reusable strict decoders; algorithms are outside the repository.
- UI: existing typed detail DTO adds learningStatus = unlearned/reviewing/mastered, converted centrally to 未学习/复习中/已熟练. Raw internal enum is not spread through Svelte. No formal mutation IPC, debug rating buttons or Today Study implementation.

## Tests

Phase 4 was revalidated before changes: frontend 6/6, check 0 errors/0 warnings, build PASS, Rust fmt/check/Clippy and all 45 Rust tests PASS.

Final local validation:

- Existing Rust tests: **45 retained**.
- New SRS tests: **19**; one golden-vector test checks **50** results generated from unchanged current Mac scheduler/policy source.
- Total Rust: **64 passed, 0 failed, 0 ignored**.
- Frontend: **7 passed, 0 failed** (existing 6 plus presentation labels).
- Svelte check: **0 errors, 0 warnings**; production static build PASS.
- Rust fmt/check/Clippy all targets with warnings denied: PASS.
- Manifest validation/drift: PASS, total **10,609**, added/removed/changed all empty. Python tooling **11/11**.

Key coverage: all states/ratings; interval 1/2/3/10/32/59/60 rounding/cap; manual Mastered; positive/negative automatic qualification; Hard/Again disruption; exact one-log cardinality; enriched history and index/tie ordering; lazy progress; duplicate stale snapshots/retry; archived/missing/suspended errors; negative/overflow/coverage errors; DST spring/fall 23/25 hours, gaps/folds, minute DST, month/year boundaries and Shanghai timezone; actual SQL/commit rollback; file-backed persistence/reopen; read-only detail presentation for every state.

The fixture contains only source input/output/rule data, not copied Swift implementation. Tests supply explicit calendars/UTC values and never depend on runner timezone. Integration databases are memory or tempfile SQLite, not Tauri development data.

## Parity

MAC/WINDOWS SRS PARITY: **READY for Phase 5 formal scheduler and persistence with explicit time context**.

StudySession, reinforcement and spelling are intentionally not implemented. Source deviations/representation choices are explicit in the spec: stale AGENTS easy rule, local-day review eligibility, lazy new progress, typed invalid data rejection, suspended service guard and deterministic equal-time log tie-break.

## macOS Tauri

**PASS**. Real Tauri dev started with Rust IPC and existing development vocabulary. AppShell/global browse 1–50 / 10,609; five exact-count cards; N1 1–50 and 51–100 / 4,029; search “高校” → two results; N5 browsing; lexical details and examples; actual “学习状态：未学习” display all passed. Tab/Enter opens books and words; Escape closes details and restores the row; keyboard pagination and Shift+Tab previous page passed.

The ignored temporary dev runner copied the current debug executable into the native development app bundle for automation. It was removed after audit. No audit UI/helper/permissions or rating buttons were added. No formal rating or bulk progress mutation was performed against existing development data; other state groups were validated with temporary database/DTO tests. App quit normally.

## Windows CI

Run / URL / native tests / SRS tests / Tauri build: pending implementation push and full native workflow.

All existing workflow gates remain; cargo test automatically discovers SRS tests. No new CI gate, artifact naming, release or installer pipeline changes needed.

## macOS Isolation

**NO SOURCE MODIFICATION**.

Phase 5 changes are restricted to `windows/**`. `Kotoba/**`, `KotobaTests/**`, `Kotoba.xcodeproj/**`, Mac resources/SwiftData/backup/seed, shared manifest/identity assignments, SQLite schema/migrations and dependency lockfiles are unchanged. Total vocabulary/counts/canonical IDs and manifest remain intact. No Mac V4 or mapping work.

## Known Limitations

- No StudySession, reinforcement, spelling, statistics, sync or auth.
- No physical Windows interactive runtime test; native CI proves compilation/tests/bundling, not full UI runtime.
- Windows signing not configured.
- CalendarContext requires explicit complete timezone rules supplied by its caller. Wiring the user's native timezone provider is future StudySession integration; no rating IPC uses an incorrect UTC default today. Historical/non-Gregorian calendar preferences and all global timezone discontinuities are not exhaustively certified.
- Mac equal-timestamp log order is unspecified; Windows uses the existing index's deterministic ID tie-break. Independent non-formal event rows, if ever introduced, require an explicit formal discriminator at that future phase.
- No progress reset, study-session controls or user-facing rating mutation UI/API.

## Phase 5 Result

Local checks, scheduler/persistence parity vectors and macOS Tauri audit PASS. Final result pending complete Windows CI.
