# Kotoba Windows Phase 4 Report

验证日期：2026-10-05。PHASE 4 — Windows Product UI Foundation + Vocabulary Browsing。

## Repository

- Branch: `feature/windows-client`.
- Base HEAD: `3de0bc8c7015bd20dc0644cbf805ed09b50d73bd`.
- Starting working tree: clean; branch matched the requested branch. Phase 3 foundation was revalidated before implementation: manifest PASS, Python 11/11, Rust 40/40.
- Implementation commit: pending commit — `Build Windows vocabulary browsing UI`.
- Final HEAD: pending CI/report finalization; final branch tip will be provided in the final chat. A report cannot embed the hash of the commit containing itself.
- No main merge, PR, tag or GitHub Release.

## Product UI

- Navigation order: 今日学习 → 单词管理 → 词书 → 学习统计 → 五十音图 → 设置.
- Implemented: 单词管理、词书、单词详情. Default entry: 单词管理.
- 今日学习、学习统计、五十音图、设置 each explicitly display “此功能将在后续阶段实现。”
- AppShell owns navigation and fixed sidebar/main layout. Route entry uses lightweight selected-section state; separate vocabulary, detail, status, service and type modules keep it small. No extra router/state/UI framework.
- Initial native window: 1100 × 760; minimum 720 × 560. Native title bar and resizing retained.
- At widths below 1100, detail replaces the list; at wider widths, list and detail are shown together. Sidebar narrows from 204 to 160 below 800. Body does not scroll; cards, list and detail have explicit content scroll ownership.
- Removed prototype wording and visible schema/manifest/canonical identity diagnostics. Internal `app_info`/`database_info` remain available, without product-page display.

## Wordbooks

All counts are Rust/SQLite query results, never frontend constants.

| Book | Words |
|---|---:|
| JLPT N5 | 802 |
| JLPT N4 | 755 |
| JLPT N3 | 1,817 |
| JLPT N2 | 3,206 |
| JLPT N1 | 4,029 |
| Total / 5 books | 10,609 |

Cards open a book-specific browser. Pages contain at most 50 words, with previous/next controls and current range/total; N1 is not serialized in full. No invented study-progress labels.

## Word Management

- Initial browse: all built-in vocabulary, first 50 of 10,609.
- Search fields: Japanese expression, reading and Chinese meaning, queried through Rust/SQLite, including book/level labels.
- Placeholder: 搜索单词、读音或中文释义. Frontend only trims and caps input at 200 characters; SQL parameters and literal `%`, `_`, `\` escaping are handled by Rust.
- Debounce: 250 ms. Every new input immediately invalidates the old request before debounce begins. LatestRead sequence guards discard late success and error responses; pending timers and reads are invalidated on unmount.
- Query changes reset offset to zero. Empty query calls bounded browsing rather than changing Phase 3 empty-search semantics.
- Loading clears stale results. Empty results show 没有找到匹配的单词. Safe Chinese errors provide retry; raw Rust/SQLite errors and filesystem paths are never rendered. Clearing search restores browsing and focuses the search input.
- Pagination resets list scroll and preserves keyboard focus. Request state is shared between mouse and keyboard actions.

## Word Detail

- Local ID lookup returns a dedicated lexical DTO or safe `null` for missing words.
- Displays expression, reading, Chinese meaning, book/level, existing part of speech, optional Japanese/Chinese example, supported tags and optional loanword information.
- Raw pitch/source diagnostic tags are filtered for presentation only; stored tags remain unchanged. Empty optional fields are safely omitted.
- Loanword source requires a nonempty term and supported language, or actual wasei metadata. Chinese-origin aliases including `chi`, `zho`, `zh` are always hidden, even with wasei/partial flags. The two current `chi` records are tested through real detail reads while storage remains intact.
- Partial and wasei labels use actual metadata. No temporary pitch or romaji parser; no fake review state, due date, interval, history or favorite mutation.

## Accessibility

- Semantic nav/main/section/header/list/button/input elements; explicit Chinese names for navigation, search, book selection, rows, pagination, close/back and retry.
- Japanese lexical text uses `lang="ja"`; document language is `zh-CN`.
- Tab/Shift+Tab navigate native controls, Enter activates buttons/word rows, Escape closes detail or returns from book browsing without exiting the app.
- Detail opening focuses its heading, closing restores the originating word row; navigation focuses the new page heading. Pager focus survives asynchronous refresh and moves to an enabled control at a boundary.
- Global `:focus-visible` has a clear 3 px semantic focus outline; no outline removal. Skip-to-main link and status/alert states are provided.
- macOS AX names and keyboard behavior were audited; this is an accessibility foundation, not a complete Windows screen-reader certification.

## Appearance

- Shared tokens define background, surface, secondary surface, primary/secondary text, border, accent, danger, focus, sidebar width, content spacing and radius. Component colors consume these tokens.
- `prefers-color-scheme` switches tokens and `color-scheme: light dark` styles native controls. No theme selector or persisted preference.
- System font stack includes system-ui, Segoe UI, Yu Gothic UI, Meiryo and PingFang SC. Japanese fallback uses system fonts; no bundled/downloaded fonts.
- Light/dark sidebar, cards, search focus, empty state, selected list row and detail are readable in the macOS WebView audit. Actual dark media-query response was verified through temporary app-window theme forcing; OS-wide appearance was not changed.
- Long meanings clamp to two list lines; detail content wraps, with independent scrolling.

## Data Architecture

- Typed frontend service: `src/lib/services/vocabulary.ts`; components do not invoke Tauri directly.
- Dedicated frontend types: WordBookSummary, VocabularyWordListItem, PagedResult, VocabularyWordDetail and LoanwordSource. No `any`.
- Dedicated Rust product DTOs and commands: `browse_books`, `browse_words`, `browse_search`, `word_detail`. JSON uses consistent camelCase via serde; internal Rust fields remain snake_case.
- Legacy Phase 3 database read methods/contracts and tests remain intact. Raw persistence models are no longer the product-facing vocabulary IPC payload.
- List/search use a joined count query plus one bounded joined page query; book names/levels are fetched together. Detail uses one joined query. Book summary uses the existing aggregate query. No row-by-row book fetch or N+1 pattern.
- List limit is validated at 1–100; the UI uses 50. Stable ordering includes book key, word key and local ID. Search values are bound parameters. Full 10,609-word payloads never reach the UI.
- Actual macOS Tauri IPC measurements using the same production service: N1 first page **30.00 ms** (50 items; total 4,029); global “高校” search **22.00 ms** (2 results). Single development observations, not a benchmark or Windows performance claim.
- Schema 2, migrations, manifest version 1, seed provenance, namespace and canonical assignments are unchanged. No vocabulary/user-state mutation commands introduced.

## Tests

- Rust: **45 passed, 0 failed, 0 ignored** locally; all original 40 tests retained plus 5 product-read tests.
- New Rust coverage: exact five-book counts/DTO field separation; global/book stable paging, invalid limits and end boundaries; detail/local ID/missing-word handling and hidden fields; book-labelled search paging, expression/reading/Chinese matching, literal wildcards/backslash, injection and length bounds; loanword policy including actual Chinese-origin records/storage preservation.
- `cargo fmt --check`, `cargo check --locked`, `cargo clippy --locked --all-targets -- -D warnings`, `cargo test --locked`: PASS.
- `npm run check -- --fail-on-warnings`: **0 errors, 0 warnings**.
- `npm run test:ui`: **6 passed, 0 failed**. Node built-in deterministic tests cover debounce/race-before-debounce, coalescing/cancellation/empty-query routing, pagination/query reset/literal text, loading/empty/error/retry mapping, detail switching/close invalidation/not-found, empty/final-page ranges. No test framework dependency added.
- `npm run build`: PASS, adapter-static output produced.
- Manifest validation: PASS; drift added/removed/changed all empty. Existing Python tooling tests: **11 passed**.
- Windows workflow adds only the lightweight frontend state-test gate; all existing native gates, release executable manifest probe and artifact generation remain enabled.

## macOS Tauri Manual Audit

Real Tauri development application with Rust IPC and app-data SQLite was exercised. A temporary ignored dev runner copied the debug executable into the development app bundle for native automation. Temporary size/theme/timing audit code and permissions were removed before the source commit; the clean product UI was reloaded successfully and the app was quit.

| Native window | WebView content | Observed result |
|---|---|---|
| 720 × 560 | 720 × 528 | Narrow sidebar; detail replaces list; close and pagination usable; no horizontal overflow |
| 900 × 700 | 900 × 668 | Comfortable narrow detail; dark text/content readable; no horizontal overflow |
| 1200 × 800 | 1200 × 768 | List/detail split; light and dark readable; no horizontal overflow |
| 1440 × 900 | 1440 × 868 | DOM/main width overflow checks false; full screenshot visibility limited by current display bounds |

The 32 px height difference is the native title bar. No custom title bar/drag region was introduced.

Verified AppShell/sidebar, five SQL-backed book cards, N5/N1 opening, 50-word pages, distinct subsequent pages, actual lexical detail/examples, Escape return and Enter reopen, Enter repeated paging, Shift+Tab previous paging, Japanese “高校”, reading “こうこう”, Chinese “高中”, literal “%” empty results, ordinary no-match search, and clearing back to 1–50 / 10,609. All four placeholder pages show the future-phase notice. Focus outlines were visible in screenshots.

Loading/error/retry races were checked deterministically; no production database corruption or artificial reset was used to force a native error. Windows physical runtime was not tested.

## Windows CI

- Run ID / URL: pending source push.
- Result: pending full native workflow.
- Native Rust tests / Tauri Windows build / artifacts: pending.

## macOS Project Isolation

**NO SOURCE MODIFICATION**.

Phase 4 delta is restricted to `windows/**` and the Windows workflow's frontend test gate. No changes to `Kotoba/**`, `KotobaTests/**`, `Kotoba.xcodeproj/**`, macOS resources/schema/seed/backup or `shared/vocabulary/**`. Branch history predates Phase 4 and already contains the approved shared vocabulary foundation.

## Not Implemented

SRS, study/review flow, spelling, statistics, sync, auth, Mac canonical mapping, CSV import, create/edit/delete/favorite/status mutation, theme/language selector, romaji and pitch presentation parity. No Release, tag, PR or main merge.

## Known Limitations

- Physical Windows UI runtime: **NOT TESTED**. CI proves native compilation, tests and bundling only.
- Windows signing is not configured.
- Romaji/pitch parity is pending. Raw pitch tags remain stored without a false UI parser.
- 1440-wide full visual capture is limited by current Mac display bounds; DOM/main overflow was measured as false.
- Runtime audit used the macOS WebView; Windows WebView2 font rendering, focus and resize behavior need later physical testing.

## Phase 4 Result

Local checks and macOS audit PASS. Final result pending full Windows CI.
