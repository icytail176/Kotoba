# Kotoba Built-in Startup Repair Report

Date: 2026-09-29  
RC baseline: `2ed854c58ef21d65d1d3a21fcf4201bec1730002`  
Scope: 0.2.0 RC startup blocker and the real-store JLPT N5 803/802 discrepancy

## 1. Error message source

The exact message `内置词书初始化未完成，将在下次启动时重试。` is the localized description of `BuiltInWordBookError.incompleteSeed` in `BuiltInWordBookService`.

`BuiltInWordBookService.loadIfNeeded` throws that error when final built-in integrity validation fails. `ContentView.loadInitialWordBooks` catches it, assigns `error.localizedDescription` to `migrationErrorMessage`, and SwiftUI presents that value in the `数据加载失败` alert. The alert was therefore reporting a real final integrity failure; it was not a database-open or SwiftData schema error.

## 2. Startup initialization call chain

The verified startup chain is:

`KotobaApp` → `KotobaDatabaseRootView` → `KotobaStore.makeDefaultContainer()` → `ContentView.task` → `BuiltInWordBookInitializationCoordinator.loadIfNeeded` → `BuiltInWordBookService.loadIfNeeded` → resource validation → incremental seed/repair → loanword sidecar apply → `ModelContext.save()` → final integrity validation → seed-version write → legacy word migration → Home.

Before this repair, `ContentView.task` called `BuiltInWordBookService` directly. No other production call site for built-in loading was found.

## 3. Seed/completion decision

- Completion marker: `UserDefaults.standard["internal.builtInWordBookSeedVersion"]`.
- Current target: `BuiltInWordBookService.builtInVocabularyVersion == 6`.
- Healthy current-version fast path: version is 6, exactly one built-in book exists for every expected level, and its active (`!isArchived`) count equals the formal count.
- The real app-domain value before repair was 5, not 6. The repeated integrity failure prevented version 6 from being written, so every launch correctly retried.
- The implementation writes version 6 only after resource validation, mutation, sidecar application, a successful save, and final integrity validation. It is not written on failure.
- No second `didSeed`, `initializationCompleted`, or `needsRetry` flag controls this path.

## 4. Real user store before health

The actual sandbox store family was located at:

`~/Library/Containers/com.fumi.Kotoba/Data/Library/Application Support/Kotoba/Kotoba.store{,-wal,-shm}`

The similarly named non-sandbox Application Support store was not used by the signed sandboxed app. Diagnosis and repair rehearsal used complete copies while Kotoba was stopped. The untouched pre-repair copy remains at `/private/tmp/kotoba-live-pre-repair.8cosnl/` for this local session.

| Book | UUID | Active | Archived | Physical | Resource expected |
|---|---|---:|---:|---:|---:|
| JLPT N5 | `71C0C7B-5E97-E4B3-F822-22297BC2D59F1` | 803 | 0 | 803 | 802 |
| JLPT N4 | `7D2A3E46-7293-42A5-854B-4584BB2101DB` | 755 | 0 | 755 | 755 |
| JLPT N3 | `3060DAF4-12E3-4D27-91B9-B4E39A97592A` | 1817 | 0 | 1817 | 1817 |
| JLPT N2 | `5A115DC2-3162-4E8A-863F-F9569D504B23` | 3206 | 0 | 3206 | 3206 |
| JLPT N1 | `F13413B5-F1EB-49D1-B154-10F30B06D4C7` | 4029 | 0 | 4029 | 4029 |

Before repair: 10,610 words, 10,610 progress objects, 85 ReviewLogs, 0 favorites, and 10,610 active built-in rows. SQLite `integrity_check` returned `ok`.

## 5. Why N5 was 803

The N5 resource contains `口 / くち`. The database contained both that resource row and a historical canonical-equivalent row `〜口 / 〜くち`. The old refresh selected the exact resource identity (`口`) as keeper. It could not delete learned `〜口`, but the later stale loop also skipped `〜口` because its equivalent key was present in the resource. As a result, both remained active, N5 stayed at 803, final count validation failed, and seed version stayed at 5.

This directly links the 803 Home value and the recurring initialization alert to the same repair-algorithm gap.

## 6. Extra/stale/duplicate row details

Database-only row before repair:

- UUID: `8D25BBBC-C770-4AAF-BA64-79D10858A011`
- expression/reading: `〜口 / 〜くち`
- meaning: `……口；股，份`
- archived: false
- favorite: false
- progress: review, interval 2 days, reviewCount 1, lapseCount 0
- dueAt: 2026-09-24 15:48:09 Asia/Shanghai
- lastReviewedAt: 2026-09-22 15:48:09 Asia/Shanghai
- ReviewLogs: 1 (`8DB9A11B-D544-4F5B-B112-877ECCD6067A`)
- createdAt: 2026-06-19 15:13:40 Asia/Shanghai
- updatedAt: 2026-09-22 15:48:45 Asia/Shanghai

Exact resource row before repair:

- UUID: `4F3D051C-FD28-4097-AA1D-A87A27B6E9F3`
- expression/reading: `口 / くち`
- active and not favorite
- pristine new progress: interval/review/lapse all zero, no last review, no ReviewLog
- createdAt: 2026-06-19 15:13:40 Asia/Shanghai

## 7. Active versus archived

Both rows were active before repair. There was no archived N5 row. Therefore this was case A from the investigation requirements—an incorrect extra active row—not a legal archived row accidentally counted by Home.

## 8. Progress state

Both objects had progress. The historical `〜口` object had meaningful review progress; the exact `口` object was pristine. Repair retained the historical object's UUID and progress object and updated only its built-in resource metadata/identity to `口 / くち`.

## 9. ReviewLog state

The historical object had one ReviewLog and the pristine object had none. The existing log and its relationship remained attached to the retained historical word. No log merge or duplicate-log creation occurred.

## 10. Favorite state

Neither real-store object was favorite. The generic repair policy nevertheless treats favorite as protected user data, and a regression test verifies that a favorite canonical-equivalent object is retained rather than deleted.

## 11. Initialization race assessment

There was no evidence that this specific pair was created by two simultaneous same-process initialization tasks. The old service was `@MainActor`, but it had no explicit shared single-flight coordinator. The two rows also represent different historical identities rather than identical inserts, and the rest of the store did not show broad duplicate seeding.

An explicit process-local single-flight coordinator was added to remove re-entry ambiguity: all concurrent callers await the same main-actor task and receive the same result. A failed task is cleared so the next call can retry.

## 12. Multi-process assessment

macOS can be forced to start another app process (for example with `open -n`), so process-local single-flight cannot be an inter-process lock. Normal application use is single-instance, and no evidence connected this real-store row to multi-process access. A complex IPC lock was therefore not added. Validation also confirmed that a forced second process did not change the repaired counts.

## 13. Root cause

The root cause was canonical-equivalent duplicate resolution order in `BuiltInWordBookService.refresh`: exact resource identity was favored before user data, and a protected equivalent row was exempted from both duplicate cleanup and stale handling. This left two active representations for one resource identity. Count validation then failed on every startup and correctly withheld seed version 6.

## 14. Repair implementation

Refresh now groups existing words by canonical equivalent identity, chooses a deterministic keeper, applies the current resource metadata to that object, and enforces one active representation:

1. Prefer active candidates, then rank user data: ReviewLog, meaningful progress, favorite, missing-progress protection.
2. Use exact resource identity only as the tie-breaker after user-data protection.
3. Apply the current resource row to the keeper and unarchive it.
4. Delete only redundant pristine objects.
5. Archive redundant protected objects.
6. Continue applying the existing safe-delete/archive policy to truly stale non-resource objects.

Resource validation also rejects duplicate canonical-equivalent rows, and final validation compares the complete active identity multiset to the parsed resource identity multiset rather than checking counts alone.

## 15. Single-flight design

`BuiltInWordBookInitializationCoordinator` is a shared `@MainActor` coordinator holding one in-flight `Task<[BuiltInWordBookLoadResult], Error>`. The first caller starts the operation; later callers await that task. Success and failure both clear the slot, so the operation is idempotent and failures remain retryable. SwiftData mutations stay serialized on the main actor and one context.

## 16. Repair policy

- Pristine duplicate/stale row: safe delete.
- ReviewLog, meaningful progress, favorite, or missing-progress row: preserve; keep as the active resource representation when possible, otherwise archive.
- Two protected duplicates: deterministically keep one active and archive the other; do not merge logs or destroy either object.
- New resource row with no existing equivalent: insert with new progress.
- Current resource identity: exactly one active representation after repair.

## 17. Data preservation strategy

The learned real object (`8D25…A011`) was retained. Its UUID, progress UUID and fields, dueAt, interval, review/lapse counts, lastReviewedAt, ReviewLog UUID and relationship, and favorite value were captured before repair and asserted identical after three repair invocations. Only bundled word metadata/identity was refreshed. The redundant pristine object (`4F3D…E9F3`) was safely deleted with its pristine progress.

## 18. Home count behavior

`HomeDashboardService` already used active-word semantics and excluded `isArchived`. The displayed 803 was therefore an accurate reflection of the polluted active store, not a Home counting bug. No production Home query change was required. Regression coverage now confirms archived built-in words are excluded from Home totals, remaining-new, due review, StudyQueue, and HomeSearch.

## 19. Regression tests added/updated

- Real `口 / 〜口` regression: learned canonical-equivalent object wins, UUID/history are preserved, final identity is current resource, repeated repair is stable.
- Two learned equivalents: one deterministic active representation, the other archived, both logs retained.
- Favorite equivalent: favorite object is retained.
- Concurrent initialization: 10 callers share one resource read and produce one word/one progress with identical results.
- Failed initialization: in-flight state clears and a later call succeeds.
- Archived built-in word: excluded from Home totals/new/due, StudyQueue, and HomeSearch.
- Debug-only copied-store diagnostic: captures all user-bearing signatures, repairs three times, and verifies real-store preservation and final counts.
- Existing clean-install, current-store fast path, partial/interrupted seed retry, parse failure, save failure, stale learned/pristine, exact duplicate, backup, migration, SRS, CSV, pagination, and performance suites remained passing.

## 20. User-store copy repair before/after

| Metric | Before | After |
|---|---:|---:|
| N5 physical | 803 | 802 |
| N5 active | 803 | 802 |
| N5 archived | 0 | 0 |
| Total active built-in | 10,610 | 10,609 |
| Total words | 10,610 | 10,609 |
| LearningProgress | 10,610 | 10,609 |
| ReviewLogs | 85 | 85 |
| Favorites | 0 | 0 |

The one removed word/progress pair was the proven pristine redundant object. SQLite integrity remained `ok`. Three successive repair calls left the result stable.

## 21. User-data preservation result

All user-bearing word signatures were unchanged. ReviewLogs stayed at 85, favorites stayed at 0, and every learned/suspended progress object's UUID and scheduling fields were preserved. The retained row after repair is UUID `8D25…A011`, now represented as active `口 / くち`, review state, interval 2, reviewCount 1, lapseCount 0, with its original ReviewLog.

## 22. First real Release launch

PASS. The signed Release app opened the real sandbox store, completed the automatic repair, wrote seed version 6, and produced N5 active 802 / total active 10,609 with SQLite integrity `ok`. No built-in initialization failure was recorded. The database was never manually replaced or reset.

## 23. Second real Release launch

PASS. After quitting and relaunching the signed Release app, Accessibility inspection showed `JLPT N5` and `词书总词数 802`; neither `数据加载失败` nor the incomplete-initialization message was present. Counts and seed version remained stable.

## 24. Third real Release launch

PASS. After another full quit/relaunch, Accessibility inspection again showed N5 total 802 and no startup alert. The real store remained at seed version 6, 10,609 active built-in rows, 85 ReviewLogs, and SQLite integrity `ok`.

An additional launch attempt after these checks restored no window and exited without altering the store; it is not counted among the three validated launches.

## 25. Final N5 count

Final real store: 802 active, 0 archived, 802 physical. The Home value is 802 because Home counts active words in the selected N5 built-in book.

## 26. Final built-in total

10,609 active built-in words: N5 802, N4 755, N3 1,817, N2 3,206, N1 4,029.

## 27. Fast-path performance

`PerformanceBaselineTests.testPerformanceBaseline` passed. Current-version healthy-store fast-path median was 5.621 ms (min 5.544 ms, max/p90 5.787 ms). It still performs count queries without reading/parsing the complete CSV resources. First-seed median was 4,286 ms.

## 28. Full XCTest result

Command:

`xcodebuild test -project Kotoba.xcodeproj -scheme Kotoba -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`

Result: 200/200 passed, 0 failed, 0 skipped, 0 runtime warnings.

Result bundle: `/Users/fumi/Library/Developer/Xcode/DerivedData/Kotoba-hggzhrmduooxvndmvxusyxgjpmrw/Logs/Test/Test-Kotoba-2026.09.29_14-21-03-+0800.xcresult`

## 29. Release result

The requested signed Release build completed with `BUILD SUCCEEDED` and 0 Swift compiler warnings. The AppIntents metadata extractor emitted its standard no-AppIntents-framework note; this is not a Swift compiler warning and is unrelated to startup/data integrity.

Artifact: `/Users/fumi/Library/Developer/Xcode/DerivedData/Kotoba-hggzhrmduooxvndmvxusyxgjpmrw/Build/Products/Release/Kotoba.app`

## 30. Version invariants

- SwiftData schema: V3, unchanged.
- Backup schemaVersion: 3, unchanged.
- Built-in seed version: 6, unchanged.
- Formal vocabulary CSVs: unchanged; counts remain 802/755/1817/3206/4029.
- Loanword sidecar: unchanged at 46 data rows.
- No third-party dependency was added.

## 31. Local commit

A local commit with message `Fix built-in vocabulary startup repair` is created only after this report, all tests, signed Release build, and the three real-launch checks pass. No push is performed. The final chat records the resulting commit hash.

## 32. Release-blocker assessment

The startup blocker is resolved. There are no new P0, P1, or P2 issues attributable to this repair. The repaired real store reaches and retains exact resource coverage, startup uses the millisecond fast path afterward, and the RC is ready to resume the manual checklist.
