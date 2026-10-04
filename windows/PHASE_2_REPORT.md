# Kotoba Windows Phase 2 Report

日期：2026-10-04。PHASE 2 — Cross-Platform Data Contract + Windows SQLite Foundation。

## Repository

- Branch: `feature/windows-client`
- Base HEAD / PHASE_1_HEAD: `0b1e24f4567f93e32b6c6cf60b8a3c6099a4f53a`（documentation-only）
- Validated Phase 1 source SHA: `956e510dff35aa848613386a9ca8c3f40a03eb00`
- 起始 working tree: clean；未覆盖用户修改。
- Final implementation HEAD: pending commit / Windows CI verification.
- 不 squash/rewrite 历史，不 merge main、不创建 PR/tag/Release。

## macOS Audit

Read-only audit；详尽字段与代码依据见 [CROSS_PLATFORM_DATA_CONTRACT.md](docs/CROSS_PLATFORM_DATA_CONTRACT.md)。

| Item | Actual source / result |
|---|---|
| Active SwiftData schema | KotobaSchemaV3, 3.0.0；KotobaSchema.swift / KotobaStore.swift |
| Frozen compatibility | KotobaSchemaV1.swift / KotobaSchemaV2.swift；lightweight V1 → V2 → V3 |
| V3 change | VocabularyWord 增加四个 loanword metadata fields；其它 core fields 同 V2 |
| Backup schema | KotobaBackupService.schemaVersion = 3；支持旧 V1 normalization、V2/V3 decode |
| Seed version | BuiltInWordBookService.builtInVocabularyVersion = 8 |
| Entities | WordBook / VocabularyWord / LearningProgress / ReviewLog |

Backup 有实体 UUID、关系 UUID、enum raw values、ISO8601 dates、可空字段、完整预检、显式 merge modes 和 save failure rollback；它不是 sync schema，日期编码不保证全部 subseconds。V1 移除字段没有重新引入 Windows。

实际 persisted states: new / learning / relearning / review / suspended。实际 ratings: again / hard / good / easy。formal easy、automatic mastery 的 good、reinforcement mastered override 分别保留真实语义；中文 presentation grouping 不替代 persisted state。现有正式日志有拼写 enrichment 和 backup overwrite 例外，不声称所有字段绝对 immutable。

## Stable ID Audit

**STABLE BUILTIN ID REQUIRES DESIGN CHANGE**

**BUILT-IN CROSS-PLATFORM ID STATUS: NOT READY**

- CSV 资源没有 UUID/immutable source key。五级共 10,609 条。
- 新内置书、makeWord 创建词和 LearningProgress 不传显式 id，默认 UUID() 随机。独立安装 A/B 不保证同词 UUID 一致。
- 现有持久化 record ID 可保持；refresh 保留匹配 keeper ID；新条目/missing progress 随机生成。
- Startup / canonical duplicate repair 按本地数据选择 keeper，其他 safe pristine 记录删除，使用过的记录归档；不同设备 keeper 可能不同。
- Metadata-only loanword enrichment 保留 word/progress/log ID；version 6/7 → 8 的完整数据可走 metadata-only，不完整则 refresh。
- expression + reading 可变，有归一化碰撞、多义与跨书重复风险，不能直接当 permanent global key。
- Phase 3 前必须由用户选择 immutable source-key + namespace UUID、source-key identity 或 shared canonical manifest，并设计既有随机 UUID aliases/history 兼容。Phase 2 不选定、不实现任何真实词条 ID 算法。

## Cross-platform Contract

Document: `windows/docs/CROSS_PLATFORM_DATA_CONTRACT.md`。

四实体逐字段记录 semantic/source/SQLite/type/nullability/persisted/sync candidate/immutability；包含 V1/V2/V3 matrix、Backup、ID、mastery/log 行为和 future risks。

Encoding：UUID canonical lowercase TEXT；日期 signed Unix UTC microseconds INTEGER；bool INTEGER 0/1；SRS/rating 稳定 TEXT；tags JSON string array；errorTypes sorted semicolon raw values。Swift Date submicrosecond 量化与 Backup ISO8601 精度差异已明确，不宣称已经完成无损跨端转换器。

Progress / log 在 Windows 必须引用有效 word；Mac SwiftData 关系 optional，Backup 预检同样要求有效非空关系。该更严格 graph boundary 已明确，未自动修复孤立数据。

## SQLite

- Library: rusqlite 0.40.2，libsqlite3-sys 0.38.2；Cargo.lock 固定解析。
- SQLite mode: bundled，原生静态编入，无独立 SQLite DLL 安装要求。
- Compatibility: 当前 stable 版本由官方 docs.rs / Cargo 解析确认；本地 Rust/Cargo 1.99.0、Tauri 2.12.1 编译通过；Windows native 结果待下方 CI 验证。
- Production path: Tauri app.path().app_data_dir() / kotoba.sqlite3；identifier com.fumi.kotoba.windows。不写 repo/cwd/exe 目录，不 hard-code 用户路径。
- Mac dev app-data 与原生 com.fumi.Kotoba SwiftData 分离；本次没有读取原生用户 SwiftData store。
- Database schema: **Windows SQLite Schema 1**，不是 SwiftData V3。
- Migration: PRAGMA user_version，IMMEDIATE transaction 原子执行 SQL + marker；失败 rollback；unknown newer version 拒绝，不删除/reset DB。
- 新库建立四表；重开 schema 1 idempotent；未来 plan migration 1 → 2 已通过隔离测试，production 只有 migration 1。
- foreign_keys = ON；busy timeout 5 秒；STRICT、PK、FK、progress word UNIQUE、bool/enum/非负 counter/UUID CHECK。

## Tables

Actual schema: `windows/src-tauri/src/db/schema_1.sql`。

| Table | Fields |
|---|---|
| word_books | id, name, book_description, created_at, updated_at, is_built_in |
| vocabulary_words | id, japanese, kana, chinese_meaning, part_of_speech, jlpt_level, example_japanese, example_chinese, tags, created_at, updated_at, is_archived, is_favorite, loanword_source_term, loanword_source_language_code, loanword_is_wasei, loanword_is_partial, word_book_id |
| learning_progress | id, word_id, state, due_at, interval_days, review_count, lapse_count, last_reviewed_at, created_at, updated_at |
| review_logs | id, word_id, reviewed_at, rating, previous_state, next_state, previous_interval_days, next_interval_days, scheduled_due_at, error_types, typed_answer, expected_answer, question_direction_raw_value, reading_wrong_count, spelling_wrong_count, repeated_wrong_count |

Indices: words_by_book(word_book_id), progress_due(due_at) partial due states, logs_by_word_date(word_id, reviewed_at DESC, id)。没有表达/读音 identity UNIQUE。

## Rust Architecture

- db/mod.rs: Database connection/open/pragmas/info + DatabaseError；所有正常运行时错误向上传递，无 unwrap()/expect()/silent reset。
- db/models.rs: typed entity UUID、UTC Timestamp、raw enums 和四实体。
- db/migrations.rs + schema_1.sql: ordered transaction migrations、supported version 与 required-column validation。
- db/repository.rs: explicit ID upsert/fetch/list、progress unique owner 与 due filter、log insert/query/scoped delete。upsert 保留 created_at，不是 sync LWW。
- db/tests.rs: 隔离 SQLite/contract tests。
- lib.rs: Tauri setup/managed Mutex/commands；新增 database_info 返回 display-safe location/schema/counts。
- +page.svelte: typed diagnostic IPC 和 Phase 2 connected placeholder。没有任意 SQL 或 mutation IPC、正式学习 UI。

## Tests

Local total: **21**；passed: **21**；failed: **0**；ignored: **0**。main/doc test targets 另有 0 tests。

| Test | Evidence / purpose |
|---|---|
| new_database_schema_one_and_empty | 新 schema 1、无词库数据 |
| file_backed_migration_crud_reopen_is_idempotent | tempfile 真实文件，四实体 CRUD，关闭/重开保持数据和 schema |
| foreign_keys_enabled_and_invalid_relationship_rejected | FK pragma 与无效关系拒绝 |
| books_insert_fetch_list_and_explicit_upsert | 书读写/list/PK 冲突显式更新 |
| vocabulary_relationship_optional_metadata_and_upsert_roundtrip | 词/书关系、nullable metadata、upsert |
| progress_roundtrip_and_one_per_word | 完整字段与 nullable 时间；one progress per word |
| progress_cannot_reparent_and_created_at_is_immutable | 不转移 owner、保留创建时间 |
| logs_append_descending_and_duplicate_id_fails | append/descending/duplicate PK 拒绝 |
| delete_one_words_logs_preserves_other_word | scoped reset delete 不影响另一词 |
| due_query_respects_internal_states_and_day_boundary | 五状态过滤、瞬间和本地 day-end 边界输入 |
| canonical_uuid_encoding | lowercase/hyphens 与 malformed 持久化表示拒绝 |
| all_srs_raw_values_roundtrip_and_unknown_rejected | 五个 raw state / unknown 拒绝 |
| all_rating_raw_values_roundtrip | 四个 rating raw value |
| timestamp_exact_microseconds_negative_epoch_and_nullable | μs integer、epoch 前时间、null |
| boolean_zero_one_invalid_integer_and_type_rejected | 0/1 与 bool 往返；invalid value/type 拒绝 |
| negative_counters_rejected | 非负约束 |
| migration_failure_rolls_back_and_preserves_file | 失败 migration 2 回滚 DDL/marker，原文件数据仍可重开 |
| future_schema_rejected_without_reset | 新版本拒绝、数据未被清空 |
| initial_migration_failure_preserves_unmanaged_data | version 0 表冲突时不删除旧表/数据，新增 DDL rollback |
| future_migration_one_to_two_preserves_data | ordered extension plan 保留 schema 1 数据 |
| errors_sorted_roundtrip_and_tags_preserve_content | error raw 排序与 Unicode/分号 tags 往返 |

Tests 仅 in-memory/tempfile；不调用 production app-data resolver，不读写真实用户 DB。Windows file-backed test 随 cargo test 执行，不能以 compile 替代。

## macOS Validation

| Check | Result |
|---|---|
| npm run check | PASS，0 errors / 0 warnings |
| npm run build | PASS，adapter-static 输出 |
| cargo fmt --check | PASS |
| cargo check | PASS（offline cached dependencies） |
| cargo clippy --all-targets -- -D warnings | PASS，含 tests |
| cargo test --locked | PASS，21 / 21 |
| macOS tauri dev | PASS：Phase 2 / IPC connected / Database connected · Schema 1 / 日文显示 |

`npm run tauri dev` 使用临时 ignored runner 将实际 dev binary 放进已有 debug .app wrapper，以便 native UI automation 识别。Vite dev URL 127.0.0.1:1420；runtime 使用本次编译的 Phase 2 代码，非旧 binary。检查后正常 quit exit 0，runner 已移除；没有删除 app-data 数据库。

## Windows CI

Pending push and full native Windows MSVC verification. Existing workflow 仅新增 `cargo test --locked` step，保留 npm ci/check/build、fmt/check/clippy、Tauri build 和 artifacts。

Run ID: pending
Run URL: pending
Status: pending
Windows cargo test: pending
Windows native temporary SQLite file test: pending
Windows Tauri build: pending

## Dependencies

新增 direct Cargo dependencies：rusqlite 0.40.2 + bundled、uuid 1.27.0、serde_json 1.0.151；uuid/serde_json 原已作为 transitive 存在，uuid 没有新增随机/namespace generation features。dev-only tempfile 3.27.0 用于测试隔离。

npm dependency changes: **none**；package.json/package-lock.json 未改变。npm audit 仍 **3 low severity development findings**（cookie → kit → adapter-static）；无 moderate/high/critical。只记录，未运行 audit fix --force。

## macOS Project Isolation

**macOS source modified: NO**。变更仅 windows/** 和 .github/workflows/windows-build.yml 的 Rust test step。没有改 Swift models/migration/Backup/UUID/seed/resources/scheduler/session/log/UI 或 Xcode project。没有运行现有 macOS 应用的用户数据操作。

## Future macOS Schema

**UNDECIDED**。跨端 built-in identity 必须设计更改，但外部 canonical manifest/alias 或独立 metadata store 可能无需 SwiftData V4；若选择增加 canonical-key/sync fields 则可能需要未来 schema migration。这里只分析，没有创建 V4。

## Known Limitations

- Built-in vocabulary not imported；stable built-in cross-platform IDs NOT READY，Phase 3 前需用户决定兼容方案。
- Windows SRS/study queue/import/statistics/spelling not implemented。
- Sync/Auth/network protocol not implemented，tombstone/ownership/conflict resolution 未定。
- 未实现 Mac/Backup/Windows 数据互导；日期量化和 orphan graph 兼容须未来 adapter 验证。
- Windows runtime still not physically tested；native Windows SQLite tests 是 CI 运行，不能当作物理 Windows UI 验证。
- Windows signing not configured。
- Schema 1 reopening checks required columns，不是外部篡改 schema 的完整 integrity fingerprint。

## Phase 2 Result

**PENDING WINDOWS CI**。本地 audit/storage/tests/UI 验证均 PASS；stable-ID gate 仍 NOT READY。本阶段允许完成不依赖真实词库身份的 SQLite infrastructure；不得据此宣称 Phase 3 的词库身份问题已解决。
