# Kotoba SRS Parity Specification

Audited on 2026-10-05 at repository base `924c4ef83e5422857f652655fd3f323270b09bf6`. Mac version context: 0.2.1, build 3 (current project settings). Current macOS source is the authority; Phase 5 changes no Swift/macOS files.

## Source files audited

- `Kotoba/Services/DefaultReviewScheduler.swift`, `ReviewScheduler.swift`, `ReviewScheduleResult.swift`, `AppSettings.swift`.
- `Kotoba/Services/AutoMasteryPolicy.swift`.
- `Kotoba/Models/LearningState.swift`, `ReviewRating.swift`, `LearningProgress.swift`, `ReviewLog.swift`.
- `Kotoba/Features/Study/StudySessionViewModel.swift`: submit guards, formal-rating preparation/save/rollback, latest formal log, spelling enrichment, reinforcement override.
- `Kotoba/Services/StudyQueueService.swift`: active scope, due selection, new selection and per-group limits.
- `Kotoba/Services/BuiltInWordBookService.swift`: eager initial progress creation.
- `Kotoba/Services/WordbookService.swift`: creation, missing-progress presentation, reset semantics.
- `KotobaTests/DefaultReviewSchedulerTests.swift`, `AutoMasteryPolicyTests.swift`, `StudySessionViewModelTests.swift`, `StudyQueueServiceTests.swift`, `WordbookServiceTests.swift`, `FinalFeatureUpdateTests.swift`.

## Persisted states and presentation

Internal states: `new`, `learning`, `relearning`, `review`, `suspended`. Presentation is a separate grouping: missing/new → 未学习; learning/relearning/review → 复习中; suspended → 已熟练. These labels are not persisted enum values.

Formal ratings are `again`, `hard`, `good`, `easy`. `easy` means explicit manual Mastered in current source. The older root AGENTS.md describes easy as 4 days / interval ×3; that is stale relative to the current scheduler and is deliberately not implemented.

## State transition table

`r` = old reviewCount, `l` = old lapseCount, `i` = old interval. `D(n)` adds n local calendar days, retaining wall time where it exists. `M(10)` adds a precise ten-minute duration. All active formal ratings increment r once.

| Pre-state | Rating | Next-state | Interval | Due | Review count | Lapse count |
|---|---|---|---:|---|---:|---:|
| new / learning | again | learning | 0 | M(10) | r+1 | l |
| new / learning | hard | review | 1 | D(1) | r+1 | l |
| new / learning | good | review | 2 | D(2) | r+1 | l |
| relearning | again | relearning | 0 | M(10) | r+1 | l+1 |
| relearning | hard | review | 1 | D(1) | r+1 | l |
| relearning | good | review | 2 | D(2) | r+1 | l |
| review | again | relearning | 0 | M(10) | r+1 | l+1 |
| review | hard | review | clamp(ceil(i×1.2),1,60) | D(interval) | r+1 | l |
| review | good, not auto | review | clamp(ceil(i×2),1,60) | D(interval) | r+1 | l |
| any active state | easy / manual Mastered | suspended | 0 | now | r+1 | l |
| qualifying review | good / automatic mastery | suspended | 0 | now | r+1 | l |
| suspended | any (Mac pure scheduler) | suspended | max(0,i) | now | r | l |

Maximum interval is the central 60-day constant. Rust uses exact integer ceil for Hard and checked arithmetic, avoiding overflow in large inputs. Negative progress/counters, unknown raw values and arithmetic overflow return typed errors rather than the Mac getters' fallback/coercion. The formal transaction service rejects suspended submissions; the pure scheduler retains the source's suspended no-op for parity vectors. Archived words are excluded by the Mac queue; the Windows service validates active/non-archived status inside the transaction, including stale submissions after archival.

## Automatic Mastery

Exact source qualification: **pre-state review**, **pre-interval exactly 60**, **not archived**, **previous formal rating good**, **current formal rating good**. The policy itself has no dueAt/elapsed-time test; normal Mac formal submissions originate in the due queue. Windows preserves that policy and exposes the matching due read service for the future StudySession.

Reaching 60 from 32 with Good does not itself master. A 60-day Hard breaks the previous-Good chain; following Good still schedules 60, and the second following Good masters. Again enters relearning and increments lapse; relearning Good returns to a 2-day interval. No reinforcement/spelling input participates.

Automatic mastery overrides the scheduled state/interval/due to suspended/0/now but retains incremented counters. Exactly one current formal log is inserted, with rating **good**, previous review/60, next suspended/0 and scheduledDueAt now. It never fabricates an easy/mastery log.

## Time semantics

Current Mac scheduler uses injected `Calendar` (default `.current`), `date(byAdding: .day)` for days and `.minute` for minutes, with duration fallback only if Foundation fails. Review due policy compares local start-of-day values, so a review due later today is already eligible. Learning/relearning require `dueAt <= now`. This differs from the prompt's uniform exact-cutoff reference; current source/tests win.

Windows stores signed UTC microseconds and accepts explicit `now` plus immutable `CalendarContext` timezone offset rules. Civil-day addition resolves target wall time against those rules, preserving wall time across 23/25-hour DST days, shifting nonexistent times forward by the gap and choosing the first repeated wall time. Minute scheduling is checked precise UTC arithmetic. Review cutoff is the next local day's start (exclusive), not `now` or UTC midnight. No runner timezone is read by tests; insufficient rule coverage returns a typed error, never an implicit UTC approximation.

The Phase 5 Rust service requires the caller to supply complete timezone rules covering the schedule horizon. There is no study/rating IPC or OS timezone selector yet; Phase 6 must wire the user's native timezone-rule provider when it introduces StudySession. Fixed UTC is an explicit caller choice, never a production default. Non-Gregorian/calendar preferences and broader historical timezone discontinuities have not been exhaustively certified.

## Progress creation and new eligibility

Mac built-in/custom word creation eagerly creates state=new progress. Windows Phase 3 seeds vocabulary without progress; Phase 5 creates the initial snapshot lazily in the first successful rating transaction, then stores the final scheduled snapshot. No pre-transaction write and no bulk creation of 10,609 rows. Missing progress remains logically new and displays 未学习.

Eligible-new service includes non-archived words with no progress or persisted new, optional book scope, bounded 1–100 pages, ordered createdAt/expression/local ID. This is equivalent to the Mac queue on eagerly initialized vocabulary and reconciles Windows' lazy representation. Mac's randomized grouping/per-group caps and complete session selection remain Phase 6 work, not a daily-cap subsystem invented here.

## ReviewLog semantics and lookup

Mac formal handler inserts exactly one log per rating: actual rating; previous/next state and interval; reviewedAt; scheduledDueAt. Again initially carries the meaning error; other formal ratings carry no error. Spelling fields are null/zero until a later enrichment.

Mac spelling updates the existing formal log. Reinforcement Again/Hard/Good is session memory only; reinforcement Mastered updates progress/word without creating/replacing a log or incrementing formal counters. Therefore **all current ReviewLog rows are formal**, including rows enriched with spelling data. Filtering typedAnswer/questionDirection/spelling counts would incorrectly discard formal history.

Mac lookup is per-word reviewedAt descending, fetchLimit 1, without a tie-breaker. Windows uses reviewedAt DESC, local UUID id ascending to make equal-microsecond order deterministic and match the existing `(word_id, reviewed_at DESC, id)` index. Equal-time order is stable but not an inferred event sequence; future sync/reinforcement models must retain explicit formal-row semantics if they ever add separate event rows. recent_review_logs is bounded 1–100 and returns a dedicated camelCase DTO.

## Persistence and duplicate submissions

Mac prepares scheduler/auto result, applies progress fields, appends/inserts one log, updates word timestamp, then saves SwiftData. Save failure rolls back the context; session memory/counts advance only after successful save. Pending rating attempts retain original time/rating for retry; isSubmittingRating, pendingRatingAttempt and answer/current-item guards prevent duplicate callback submission. This is not a network idempotency contract.

Windows uses `BEGIN IMMEDIATE`: check active word → fetch progress → compare exact caller snapshot → fetch latest formal log via index → schedule → upsert progress → insert one log → update word timestamp → commit. CommittedReview is returned only after commit succeeds. Any domain, SQL or commit error rolls back progress creation/update, log and word timestamp. IDs are local UUID v4; word references remain Windows local IDs.

The required expected-progress snapshot (`None` means absent) makes duplicate callback submissions detectable: the second stale snapshot fails with StaleProgress. An explicit retry after rollback succeeds with the same snapshot. This complements, rather than replaces, Phase 6's session pending-save guard. No idempotency token, new schema or sync identity fields.

## Reset audit — not implemented

Mac word reset retains/reuses progress ID (or creates missing progress), sets new/due now/interval 0/reviewCount 0/lapseCount 0/lastReviewedAt nil/updatedAt now, removes that word's logs and saves atomically; failure rolls back. Book reset applies analogous behavior to that book. The Windows Phase 5 API/UI exposes no reset operation.

## Golden fixtures and validation

`windows/tests/fixtures/srs-parity.json` contains **50 input/output vectors** generated by compiling the unchanged current Mac DefaultReviewScheduler and AutoMasteryPolicy, with explicit Gregorian calendars and the audited 60-day constant. No Swift implementation is copied into the fixture or Rust tests. Vectors cover all states/ratings, boundary intervals 1/2/3/10/32/59/60, manual/automatic mastery, negative qualification, month/year boundaries, Shanghai, LA spring/fall, nonexistent/repeated wall time and minute DST crossing. LA offset transitions are explicit Foundation-derived 2025–2028 rules.

Rust also tests file-backed reopen, exact log cardinality, enrichment-aware history/index use, deterministic tie order, typed invalid/overflow/coverage errors, due/new/archive/suspended queries, presentation, snapshot duplicate rejection, checkpoint failures, real SQL failures before/after log insertion and an actual deferred-foreign-key **commit failure**. Automatic mastery rollback retries once without duplicating its Good log.

## Deliberate non-implementations and open parity risks

No StudySession, reinforcement, spelling, reset UI, statistics, sync/auth, native timezone preference/provider wiring or physical Windows interactive runtime. Calendar-rule injection is ready for the future session integration; host timezone acquisition remains explicit integration work. Current formal-row assumption must be revisited if future event models introduce independent non-formal rows. Same-microsecond Mac lookup has no stable source order; Windows documents its deterministic tie-break. No Mac bug or historical AGENTS.md discrepancy was repaired as part of Phase 5.

MAC/WINDOWS SRS PARITY: **READY for Phase 5 formal scheduler/persistence with explicit time context**. This does not claim complete StudySession/reinforcement/spelling/runtime parity.
