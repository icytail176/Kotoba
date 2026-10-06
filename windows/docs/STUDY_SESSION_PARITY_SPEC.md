# StudySession parity specification — Phase 6

Audited against current macOS source at `a0f640a3d87087da8154e45f53378cd879ea4bac` (Mac 0.2.1, build 3). Actual source wins over an earlier prompt or report. No Mac files are changed.

## Sources audited

- `Kotoba/Services/StudySession.swift`, `StudyQueueService.swift`, `SpellingQuestionService.swift`, `AppSettings.swift`, `HomeDashboardService.swift`, `WordbookService.swift`.
- `Kotoba/Features/Study/StudySessionViewModel.swift`, `SpellingSessionViewModel.swift`, `StudyFlowState.swift`, `StudyShortcut.swift`, `StudyView.swift`, `StudyCardView.swift`, `SpellingView.swift`, `StudySummaryView.swift`.
- `Kotoba/Features/Home/TodayStudyView.swift`, `HomeDashboardViewModel.swift`; `Kotoba/Components/KeyboardShortcutReference.swift`.
- `KotobaTests/StudySessionViewModelTests.swift`, `SpellingAndConjugationTests.swift`, `StudyQueueServiceTests.swift`.
- Phase 5 report and `windows/docs/SRS_PARITY_SPEC.md`; existing scheduler, mastery policy, atomic repository and tests remain authoritative.

## Queue and Today Study

Today Study resolves the selected wordbook, falling back to the first available book. It exposes **separate** L/new-only and R/due-only groups, not an invented combined daily group. Defaults: 10 new (1–100), 20 review (1–200), randomized. Rust clamps limits and selects IDs before fetching bounded lexical cards. Mixed mode remains a service/test option with independent caps.

Active scope excludes archived words and suspended progress. Missing Windows progress is logically new; no eager creation of 10,609 rows. New progress qualifies regardless of due date. Learning/relearning qualifies at the exact minute `due <= now`; review qualifies through the current local day, including a later time today. Nonrandom queues place reviews before new words with deterministic due/creation ordering. Random sampling/shuffling preserves independent category caps; exact random sequences need not agree across platforms.

Availability, scope, eligibility, queue and scheduling are Rust-authoritative. Svelte never calculates due or SRS. Host time rules are resolved through Core Foundation on Mac and native Win32 dynamic/year-specific timezone APIs on Windows, covering three days before through 65 days after the requested clock. No UTC/Tokyo/Shanghai fallback; safe timezone failure blocks formal writes. Win32 tests read installed Pacific, Lord Howe and UTC rules without changing host settings.

## Session phases and boundaries

Idle → loading → formal flashcard → appended Again reinforcement → expression spelling (including its retries) → Han reading spelling (including its retries) → summary → completed. Empty-before-start, cancelled and error are distinct states. Question order, current input, retry queues, hint/feedback state and session position live only in memory. Schema remains 2; closing the app does not resume an unfinished session. Committed formal results survive exit/reopen.

## Formal ratings and mastery

Reveal is required before 1/Again, 2/Hard, 3/Good or Delete/Backspace/Manual Mastered (Easy). Preparation retains the exact expected progress, rating and original clock. The existing Phase 5 Rust service commits progress, **one formal log**, and word timestamp atomically before returning. Only then does the controller record an outcome or advance. Pending blocks repeat/double submissions and exit. Save failure keeps the current card/snapshot, permits identical retry or returning to the card; stale snapshot invalidates with a safe restart message.

Formal Again appends one reinforcement appearance at the tail; other formal ratings do not. Formal Easy persists suspended/interval zero with one Easy log. Automatic mastery is triggered only by the existing formal Good policy; it remains one **Good** log, never fake Easy. Both mastered cases are excluded from reinforcement/spelling candidates. All ordinary new/review/relearning intervals and 60-day caps remain Phase 5 behavior.

## Reinforcement

Again/Hard/Good update only the session result/retry count and queue: Again appends to the tail; Hard/Good continue. They have no scheduler, progress, timestamp, save or log mutation path.

Mastered is a separate atomic override: suspended, interval zero, due now, updated timestamp now, word timestamp now. It retains review/lapse counters and lastReviewedAt and preserves the original formal log/rating. On failure, no memory mastery/advance is fabricated; retry retains the original prepared attempt. After commit, all later appearances and spelling candidates for that word are removed. Reinforcement does not invoke automatic mastery.

## Spelling round 1, hint and first-pass semantics

Unique nonmastered formal outcomes qualify, including kana-only expressions and Again/Hard/Good ratings. Trimmed empty expression/reading/prompt skips a question. Chinese meaning plus example context prompts the expression; all literal occurrences of the expression in the trimmed Japanese example are masked with `＿＿＿＿`. Chinese translation is shown when context exists.

Return submits. Wrong input stays on the same unlocked question, increments the phase wrong count and records the last raw wrong answer/expected answer/direction. Correct input locks feedback; another Return advances. If that appearance had a wrong attempt or used hint, exactly one tail retry is appended on correction. A clean later pass is required before leaving the round. A clean first appearance is first-pass; a clean requeued appearance is retry-pass. Counts are per unique word, not number of appearances.

Cmd-Shift-H on Mac / Ctrl-Shift-H on Windows displays the reading only in round 1. Hint is unavailable while composing, locked, pending or already shown. Hint permanently marks the word's round-one result and forces requeue; no first-character hint. All round-one retries finish before round two starts.

## Spelling round 2 and exact normalization

Expression → reading, only the exact current Mac CJK unified/compatibility ranges, including supplementary planes and extension I. Kana-only, Latin and `〇` are excluded. Empty prompts are skipped. No hint, romaji, fuzzy comparison or vowel guessing. Wrong/correct/lock/requeue semantics match round one.

Normalization follows actual `AnswerChecker`: Foundation whitespace/newline trimming, compatibility mapping, removal of ASCII/fullwidth spaces; reading maps U+30A1–30F6 katakana to hiragana. The normalized reading must be nonempty and contain only U+3041–3096 or U+30FC, then compare exactly with Swift's canonical string equality.

**Source-generated edge cases:** Foundation also trims U+200B but retains U+FEFF. Halfwidth voiced/semi-voiced marks expand to combining U+3099/U+309A without recomposition in the current Foundation compatibility mapping. Thus current Mac rejects a reading answer such as halfwidth `ｶﾞ` after its kana-only scalar guard; Windows deliberately preserves this observed behavior. Ordinary precomposed/decomposed fullwidth kana and katakana behave as Mac does. Expression equality uses canonical equivalence. `windows/tests/fixtures/mac-spelling-golden.json` contains 60 results compiled from the actual Swift service with a temporary model stub (Swift 6.4 on this Mac), not a copied checker. No Mac source was edited to generate them.

## Persistence and ReviewLog invariants

Every successful formal card rating inserts exactly one log. Reinforcement and spelling insert **zero**. At spelling completion, each word's session-specific original formal log ID is enriched atomically, not the latest history row queried later:

- `typedAnswer`, `expectedAnswer`, `questionDirectionRawValue`: last wrong submission across both rounds, or nil when none.
- `spellingWrongCount`, `readingWrongCount`: actual phase wrong attempts.
- `errorTypes`: union of original formal errors with spelling/reading and their corresponding direction errors.
- `repeatedWrongCount`: untouched (no invented value).

No rating, formal transition, review time, due, interval, progress or word timestamp is rewritten by enrichment. Multirow SQL failure rolls back all diagnostics while retaining previous formal commits. Retry reuses entries; “继续完成” may finish with in-memory summary after diagnostic save failure, matching Mac. Zero eligible spelling questions need no diagnostic write.

## Keyboard, IME, favorite, summary and exit

One central study keyboard dispatcher and one Today Study window listener implement the same mapping used by help. Mac's primary modifier is Command; Windows uses Control. Home: L/R, primary-F search, ↑/↓ suggestion selection, Enter open, Escape close. Cards: Space, 1/2/3, Delete/Backspace, F, Escape. Spelling: Return, round-one primary-Shift-H, Escape. Summary: Return. Native dialog focus trapping pauses study shortcuts. Unmodified study actions ignore editable fields except the dedicated spelling Enter; modified search/hint have explicit contexts. `event.repeat`, pending save, dialog, `isComposing`, keyCode 229 and the composition guard all block dispatch.

Composition start/end update the guard; compositionend does not submit. An event-turn ending guard additionally blocks the trailing IME commit Enter. Enter/Escape/Space/numbers/Delete/Backspace/F are left to the IME while marked. Actual Japanese input in the Mac Tauri WKWebView is audited separately; that cannot certify physical Microsoft IME behavior.

Favorite uses an atomic expected-boolean update and changes UI only after success; failure retains its previous display. It changes word favorite/update time only, never progress, logs or position.

Summary counts unique formal outcomes, their original ratings with mastered overrides, new/lapse totals, per-word retry counts and both rounds' first-pass/retry/hint metrics. The completion action is guarded exactly once for Return/button/repeated events. Active Escape opens confirmation; continuing retains the current question, exiting discards only temporary state and leaves committed history. Header/sidebar departure uses the same guard.

## Known parity limits

Phase 6 study-flow parity is distinct from complete Mac product parity. No romaji/pitch/conjugation-page presentation, secondary card arrow paging, speech, statistics, forecast, sync, auth, CSV, backup or expanded settings is added. Help lists only implemented actions. JP Intl numeric summary ordering approximates Mac localizedStandardCompare; exact collation and random order are not guaranteed. Group counts/selected-book preference are Windows local UI preferences rather than a port of the entire Mac settings screen. Native providers use the current system Gregorian timezone rules; broader historical/non-Gregorian discontinuities are not exhaustively certified. Windows signing and physical interactive Windows/Microsoft IME remain untested.
