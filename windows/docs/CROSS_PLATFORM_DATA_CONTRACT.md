# Kotoba Cross-Platform Logical Data Contract

审计日期：2026-10-05。Phase 3 baseline：`feature/windows-client`，Phase 2 final HEAD `ab7cb58a0fa819d08eef9b97ee6dda30d8324d3a`；当前磁盘 Mac seedVersion 8 / SwiftData V3 只读审计。

## Purpose and current identity status

Phase 3 now establishes a checked-in canonical manifest and separate local/canonical identity. This remains a logical model document, not a network sync protocol or Backup replacement.

**CANONICAL ID SYSTEM: READY** — namespace `01dfa402-05c2-46ab-a30f-acd35aa26ac0`, manifestVersion 1, 10,609 immutable canonical word IDs and five canonical book IDs.

**WINDOWS CANONICAL ID MAPPING: IMPLEMENTED** — independent local UUID v4 plus nullable canonical_id / canonical_key in SQLite Schema 2. Built-in importer requires canonical identity; custom/legacy rows may retain null.

**MACOS CANONICAL ID MAPPING: NOT IMPLEMENTED** — current Mac random local UUIDs still do not identify the same built-in entry across independent installs. They are retained, never uploaded as global lexical identity.

**Future macOS schema: RECOMMENDED V4**, analytically: add nullable canonicalID to WordBook/VocabularyWord while preserving local UUIDs and all learning relationships/history. The runtime/schema change is not performed in Phase 3.

Manifest source of truth and update rules: `shared/vocabulary/canonical_vocabulary.json`, its schema/identity ledger, and `shared/vocabulary/README.md`. IDs are UUID v5(namespace, immutable canonicalKey), books use name `book:` + key. Neither mutable lexical fields nor current CSV index calculate IDs after bootstrap. Ledger reservations and fixed vectors protect identity; added/removed/changed source drift is detected without regeneration.

## macOS current schema source

Read-only audit sources（路径相对 repository root）：

- `Kotoba/Models/KotobaSchema.swift`：active `KotobaSchemaV3`，version `3.0.0`，四个顶层模型；V1 → V2 → V3 均为 lightweight migration。
- `Kotoba/Services/KotobaStore.swift`：实际 container 采用上述 schema / migration plan。
- `Kotoba/Models/KotobaSchemaV1.swift`、`KotobaSchemaV2.swift`：嵌套 frozen compatibility models，仅服务旧 store migration。
- `Kotoba/Models/WordBook.swift`、`VocabularyWord.swift`、`LearningProgress.swift`、`ReviewLog.swift`：V3 字段和关系。`LearningProgress.swift` 同时定义 `StudyDuePolicy`。
- `Kotoba/Models/LearningState.swift`、`ReviewRating.swift`：真实 persisted raw values。
- `Kotoba/Services/KotobaBackupService.swift`：Backup V3 DTO、编码、预检、merge 和 rollback。
- `Kotoba/Services/BuiltInWordBookService.swift`、`CSVImportService.swift`、`BuiltInWordBookInitializationCoordinator.swift`：seed、归一化、repair、enrichment 与串行加载。
- `Kotoba/Services/DefaultReviewScheduler.swift`、`AutoMasteryPolicy.swift`、`WordbookService.swift`，`Kotoba/Features/Study/StudySessionViewModel.swift`、`SpellingSessionViewModel.swift`、`Kotoba/Services/SpellingQuestionService.swift`：评分、熟练、日志补充与 reset。
- `KotobaTests/BuiltInWordBookServiceTests.swift`：现有 repair/enrichment 测试证明的是本地已有记录的保留，不是跨安装 ID 复现。

### V1 / V2 / V3 compatibility matrix

下表同组字段逐个均具有所列版本状态；不存在的旧字段不重新引入 Windows。

| Entity / fields | V1 | V2 | V3 active | Windows requirement | Sync relevance |
|---|---|---|---|---|---|
| WordBook: id, name, bookDescription, createdAt, updatedAt, isBuiltIn, words | 有 | 同 V1 | 同 V2 | 映射全部 scalar，words 由 FK 派生 | 内容、身份与关系候选 |
| VocabularyWord: id, japanese, kana, chineseMeaning, partOfSpeech, jlptLevel, exampleJapanese, exampleChinese, tags, createdAt, updatedAt, isArchived, isFavorite, wordBook, progress, reviewLogs | 有 | 同 V1 | 同 V2 | 映射 scalar/FK，逆关系派生 | 内容、学习数据与用户偏好候选 |
| VocabularyWord.loanwordSourceTerm | 无 | 无 | String? | 可空 TEXT | 词源元数据候选 |
| VocabularyWord.loanwordSourceLanguageCode | 无 | 无 | String? | 可空 TEXT | 词源元数据候选 |
| VocabularyWord.loanwordIsWasei | 无 | 无 | Bool，default false | INTEGER 0/1 | 词源元数据候选 |
| VocabularyWord.loanwordIsPartial | 无 | 无 | Bool，default false | INTEGER 0/1 | 词源元数据候选 |
| LearningProgress: id, stateRawValue, dueAt, intervalDays, reviewCount, lapseCount, lastReviewedAt, createdAt, updatedAt, word | 有 | 保留 | 同 V2 | 映射全部 | 进度候选；并发合并待设计 |
| LearningProgress.reviewLevel | Int | 删除 | 无 | 不引入 | 非当前 baseline |
| LearningProgress.totalCorrectCount | Int | 删除 | 无 | 不引入 | 非当前 baseline |
| LearningProgress.totalWrongCount | Int | 删除 | 无 | 不引入 | 非当前 baseline |
| LearningProgress.consecutivePerfectCount | Int | 删除 | 无 | 不引入 | 非当前 baseline |
| LearningProgress.consecutiveWrongCount | Int | 删除 | 无 | 不引入 | 非当前 baseline |
| LearningProgress.meaningMastery | Int | 删除 | 无 | 不引入 | 非当前 baseline |
| LearningProgress.readingMastery | Int | 删除 | 无 | 不引入 | 非当前 baseline |
| LearningProgress.spellingMastery | Int | 删除 | 无 | 不引入 | 非当前 baseline |
| LearningProgress.conjugationMastery | Int | 删除 | 无 | 不引入 | 非当前 baseline |
| LearningProgress.firstLearnedAt | Date? | 删除 | 无 | 不引入 | 非当前 baseline |
| ReviewLog: id, reviewedAt, ratingRawValue, previousStateRawValue, nextStateRawValue, previousIntervalDays, nextIntervalDays, scheduledDueAt, errorTypesRawValue, typedAnswer, expectedAnswer, questionDirectionRawValue, readingWrongCount, spellingWrongCount, repeatedWrongCount, word | 有 | 保留 | 同 V2 | 映射全部 | 正式事件及拼写补充候选 |
| ReviewLog.formTypeRawValue | String? | 删除 | 无 | 不引入 | 非当前 baseline |
| ReviewLog.reviewLevelBefore | Int | 删除 | 无 | 不引入 | 非当前 baseline |
| ReviewLog.reviewLevelAfter | Int | 删除 | 无 | 不引入 | 非当前 baseline |
| ReviewLog.conjugationWrongCount | Int | 删除 | 无 | 不引入 | 非当前 baseline |
| ConjugationRecord（整个 entity） | 有 | 移除 | 无 | 不建表 | 不属于当前四实体模型 |
| SpeechTuningRecord（整个 entity） | 有 | 移除 | 无 | 不建表 | 不属于当前四实体模型 |

Windows SQLite **Schema 2** 是当前独立 physical version（历史 Schema 1 通过 migration 2 保留并扩展），不叫 SwiftData V3。数据库 migration、shared manifestVersion 1、Mac seedVersion 8 与 SwiftData/Backup version 分别维护。

## Logical entities and Windows SQLite mapping

每张表的 `Persist` / `Sync?` / `Immutable` 都是显式属性。`Y?` 表示未来候选，尚未决定哪些字段应同步、按用户隔离或由 canonical vocabulary manifest 管理。Immutable 是 Windows repository 的业务边界，不声称 Swift 的 `var` 或外部 SQL 绝对不可改。UTCμs / UUID / Bool / Enum 的实际编码见后文。

### WordBook → word_books

| Logical name | macOS source field | SQLite field / type | Null? Mac / Win | Persist | Sync? | Immutable | Meaning / notes |
|---|---|---|---|---|---|---|---|
| id | id: UUID | id TEXT UUID PK | N / N | Y | Y? | Y | 本地书记录身份，构造器默认随机 UUID；不是稳定内置书 canonical ID |
| name | name: String | name TEXT | N / N | Y | Y? | N | 显示名称；不用于 identity |
| description | bookDescription: String | book_description TEXT | N / N | Y | Y? | N | 描述，可为空串 |
| createdAt | createdAt: Date | created_at INTEGER UTCμs | N / N | Y | Y? | Y | 创建时间；同 ID upsert 保留旧值 |
| updatedAt | updatedAt: Date | updated_at INTEGER UTCμs | N / N | Y | Y? | N | 调用方提供的修改时间；不自动解决冲突 |
| isBuiltIn | isBuiltIn: Bool | is_built_in INTEGER Bool | N / N | Y | Y? | N | 内置标志不证明跨安装身份 |
| words | words: [VocabularyWord] cascade | vocabulary_words.word_book_id FK 逆查询 | 无集合 null | Mac relationship / Win derived | 关系候选 | N | 删除书会级联词及其依赖；无删除书 IPC |

### VocabularyWord → vocabulary_words

| Logical name | macOS source field | SQLite field / type | Null? Mac / Win | Persist | Sync? | Immutable | Meaning / notes |
|---|---|---|---|---|---|---|---|
| id | id: UUID | id TEXT UUID PK | N / N | Y | Y? | Y | 持久化记录身份；built-in 跨平台 已由独立 manifest 建立（Mac 映射未实现） |
| expression | japanese: String | japanese TEXT | N / N | Y | Y? | N | 日语写法，可能修订，不作为 PK |
| reading | kana: String | kana TEXT | N / N | Y | Y? | N | 假名读音，可修订，不作为 PK |
| meaningChinese | chineseMeaning: String | chinese_meaning TEXT | N / N | Y | Y? | N | 中文释义 |
| partOfSpeech | partOfSpeech: String | part_of_speech TEXT | N / N | Y | Y? | N | 开放字符串，空串允许；不擅自建 enum |
| jlptLevel | jlptLevel: String | jlpt_level TEXT | N / N | Y | Y? | N | 等级字符串，不当作全局 identity |
| exampleJapanese | exampleJapanese: String | example_japanese TEXT | N / N | Y | Y? | N | 日文例句，可为空串 |
| exampleChinese | exampleChinese: String | example_chinese TEXT | N / N | Y | Y? | N | 中文例句，可为空串 |
| tags | tags: [String] | tags TEXT JSON string array | N / N | Y | Y? | N | 保留数组顺序、Unicode、空串及分号；不逗号拼接 |
| createdAt | createdAt: Date | created_at INTEGER UTCμs | N / N | Y | Y? | Y | 同 ID upsert 不替换 |
| updatedAt | updatedAt: Date | updated_at INTEGER UTCμs | N / N | Y | Y? | N | 内容、偏好和 enrichment 的修改时间 |
| isArchived | isArchived: Bool | is_archived INTEGER Bool | N / N | Y | Y? | N | 归档状态；不是删除/tombstone |
| isFavorite | isFavorite: Bool | is_favorite INTEGER Bool | N / N | Y | Y? | N | 用户收藏；需未来用户作用域 |
| loanwordSourceTerm | loanwordSourceTerm: String? | loanword_source_term TEXT | Y / Y | Y | Y? | N | 词源原词，nil 与空串有别 |
| loanwordSourceLanguageCode | loanwordSourceLanguageCode: String? | loanword_source_language_code TEXT | Y / Y | Y | Y? | N | 来源语言代码，保留现值 |
| loanwordIsWasei | loanwordIsWasei: Bool | loanword_is_wasei INTEGER Bool | N / N | Y | Y? | N | 和制外来语标志，V3 默认 false |
| loanwordIsPartial | loanwordIsPartial: Bool | loanword_is_partial INTEGER Bool | N / N | Y | Y? | N | 部分外来语标志，V3 默认 false |
| wordBookID | wordBook: WordBook? | word_book_id TEXT UUID FK | Y / Y | Y | Y? | N | 可空；有值必须引用已存在书 |
| progress | progress: LearningProgress? cascade | learning_progress.word_id UNIQUE 逆查询 | 可无 progress | Mac relationship / Win derived | 关系候选 | N | 0..1 progress，不把 absence 自动变为实体 |
| reviewLogs | reviewLogs: [ReviewLog] cascade | review_logs.word_id 逆查询 | 无集合 null | Mac relationship / Win derived | 关系候选 | N | 0..many logs，不存重复 ID 数组 |

### LearningProgress → learning_progress

| Logical name | macOS source field | SQLite field / type | Null? Mac / Win | Persist | Sync? | Immutable | Meaning / notes |
|---|---|---|---|---|---|---|---|
| id | id: UUID | id TEXT UUID PK | N / N | Y | Y? | Y | 独立记录 UUID，不从 word_id 派生 |
| wordID | word: VocabularyWord? | word_id TEXT UUID UNIQUE FK | Y / N | Y | Y? | Y | Windows 仅保存完整关联的有效进度；同 ID 不允许换 owner |
| state | private stateRawValue / state | state TEXT Enum | N / N | Y | Y? | N | 五种 internal state 全保留 |
| dueAt | dueAt: Date | due_at INTEGER UTCμs | N / N | Y | Y? | N | 绝对时间；review due 判定还依赖本地 calendar |
| intervalDays | intervalDays: Int | interval_days INTEGER >=0 | N / N | Y | Y? | N | 调度结果。Schema 不施加 60 天 cap，以免损坏旧记录；cap 属于未来 scheduler |
| reviewCount | reviewCount: Int | review_count INTEGER >=0 | N / N | Y | Y? | N | 正式评分计数，非可安全跨设备相加的 counter |
| lapseCount | lapseCount: Int | lapse_count INTEGER >=0 | N / N | Y | Y? | N | 遗忘计数；同步合并未定 |
| lastReviewedAt | lastReviewedAt: Date? | last_reviewed_at INTEGER UTCμs | Y / Y | Y | Y? | N | 无正式复习时 null，不用 epoch 0 代替 |
| createdAt | createdAt: Date | created_at INTEGER UTCμs | N / N | Y | Y? | Y | 同 ID upsert 保留 |
| updatedAt | updatedAt: Date | updated_at INTEGER UTCμs | N / N | Y | Y? | N | Swift state setter 改为 Date()；Rust 接收 caller 时间，不含 scheduler/clock |

macOS 关系的 Optional 不等于合法备份可以有 orphan。Backup 预检要求 progress/log 的 wordID 非空且存在。Windows 采用该完整图约束；未来接入孤立旧实体时需显式 repair/quarantine 决策，不自动丢弃或伪造关联。

### ReviewLog → review_logs

| Logical name | macOS source field | SQLite field / type | Null? Mac / Win | Persist | Sync? | Immutable | Meaning / notes |
|---|---|---|---|---|---|---|---|
| id | id: UUID | id TEXT UUID PK | N / N | Y | Y? | Y | 正式事件去重身份；重复 insert 报错，不替换 |
| wordID | word: VocabularyWord? | word_id TEXT UUID FK | Y / N | Y | Y? | Y | 一个词的正式事件 |
| reviewedAt | reviewedAt: Date | reviewed_at INTEGER UTCμs | N / N | Y | Y? | Y* | 正式评分时间；descending query，id 作同时间 tie-break |
| rating | private ratingRawValue / rating | rating TEXT Enum | N / N | Y | Y? | Y* | again / hard / good / easy，保留真正 formal rating |
| previousState | private previousStateRawValue / previousState | previous_state TEXT Enum | N / N | Y | Y? | Y* | 评分前 internal state |
| nextState | private nextStateRawValue / nextState | next_state TEXT Enum | N / N | Y | Y? | Y* | 正式调度结果，不被强化熟练改写 |
| previousIntervalDays | previousIntervalDays: Int | previous_interval_days INTEGER >=0 | N / N | Y | Y? | Y* | 正式事件前 interval |
| nextIntervalDays | nextIntervalDays: Int | next_interval_days INTEGER >=0 | N / N | Y | Y? | Y* | 正式事件后 interval |
| scheduledDueAt | scheduledDueAt: Date | scheduled_due_at INTEGER UTCμs | N / N | Y | Y? | Y* | 正式事件安排的 due；不保证等于当前 progress.dueAt |
| errorTypes | errorTypesRawValue / errorTypes | error_types TEXT sorted semicolon raw list | N / N | Y | Y? | N* | meaning / reading / spelling / expressionDirection / readingDirection；空串表示空集合 |
| typedAnswer | typedAnswer: String? | typed_answer TEXT | Y / Y | Y | Y? | N* | 可由拼写阶段补充 |
| expectedAnswer | expectedAnswer: String? | expected_answer TEXT | Y / Y | Y | Y? | N* | 可由拼写阶段补充 |
| questionDirectionRawValue | questionDirectionRawValue: String? | question_direction_raw_value TEXT | Y / Y | Y | Y? | N* | 当前 SpellingQuestionDirection 为 meaningToExpression / expressionToReading；保留 raw，未加封闭 CHECK |
| readingWrongCount | readingWrongCount: Int | reading_wrong_count INTEGER >=0 | N / N | Y | Y? | N* | 拼写阶段读音错误计数 |
| spellingWrongCount | spellingWrongCount: Int | spelling_wrong_count INTEGER >=0 | N / N | Y | Y? | N* | 拼写错误计数 |
| repeatedWrongCount | repeatedWrongCount: Int | repeated_wrong_count INTEGER >=0 | N / N | Y | Y? | N* | 重复错误计数 |

`*`：repository 不提供任何 log UPDATE，只有 insert/query/显式 reset delete；当前 macOS 会补充错误元数据，Backup overwriteByID 还允许替换同 ID 日志。未来同步需定义 finalize/revision/enrichment 策略，不能声称现有所有字段已不可变。ReviewLog 当前没有 createdAt / updatedAt，不发明这些历史时间。

## Historical Mac local-ID audit and Phase 3 canonical identity

四实体持久化身份均为 `@Attribute(.unique) id: UUID`，构造器默认 `UUID()`。已有记录被保存、备份/恢复时保持这个 UUID。UUID 格式标准化只解决编码一致，不解决同词条跨安装 canonical identity。

### Actual source → seed → repair → enrichment path

`Kotoba/Resources/eggrolls_kotoba_N{5,4,3,2,1}_strict.csv` 的字段是 expression, reading, meaningChinese, partOfSpeech, exampleJapanese, exampleChinese, jlptLevel, tags；没有 UUID 或 immutable source key。N5/N4/N3/N2/N1 分别 802/755/1817/3206/4029 条，总计 **10,609**。

`BuiltInWordBookService.builtInVocabularyVersion = 8`；本地标记 key 为 `internal.builtInWordBookSeedVersion`。`loadIfNeeded` 先校验资源，再按 isBuiltIn + name 查找本地书；新 WordBook、`makeWord(from:wordBook:now:)` 新词以及新 LearningProgress 都不传显式 id，落到随机 UUID 默认值。资源顺序和确定的 createdAt 排序不能使 UUID 确定。

校验/repair 分别用 exact expression+reading 与 equivalent key，涉及 trim、前导 `〜` 与片/平假名归一化。它们是本地匹配策略，不是不可变、全局唯一的 lexical key。`CSVImportService.VocabularyWordImportKey` 另有 trim 后的 japanese+kana 匹配，两者也不应混为一个 identity 算法。

| Question | Evidence-based answer |
|---|---|
| A. 当前每条已保存词是否有稳定 UUID？ | 有持久化 record UUID；保存后可保留。没有共享 canonical lexical UUID 的保证。 |
| B. 独立全新安装 A/B 是否一定同 UUID？ | **否**。无资源 ID、无 namespace hash；book/word/progress 默认随机 UUID。 |
| C. seedVersion 更新保持 UUID？ | 匹配到并保留的 existing keeper 维持 ID；新增词随机生成，pristine stale/duplicates 可能删除，使用过的 stale 可能归档。不是所有历史 ID 一律保留。 |
| D. startup repair 保持 UUID？ | 保留已有匹配实体；补缺失词/progress 使用新随机 UUID。并发 load coordinator 只串行化，不生成 deterministic ID。 |
| E. canonical duplicate repair 保持 UUID？ | 只保留选中 keeper 的 ID。选择考虑已有 history/progress/favorite、exact key、createdAt 和 ID；其他记录删除（安全 pristine）或归档。不同设备 history 不同，keeper 也可能不同。 |
| F. metadata-only enrichment 保持 UUID？ | 是，修改词源/词性等字段和 updatedAt，不重建 word/progress/log。version 6/7 → 8 在完整性成立时走 metadata-only；不完整仍可能 refresh。 |
| G. expression / reading 可安全作为 identity？ | **不能直接认定**。可编辑、正字变体/归一化碰撞、跨书重复、同写法读音多义及资源修订均存在。当前局部去重不证明全球唯一且不可变。 |

依据：`BuiltInWordBookService.swift` 的 `loadIfNeeded`、`makeWord`、`refresh`、`preferredKeeper`、equivalent-key/integrity 检查、词源 sidecar 应用；模型默认 id；对应本地保留测试。

### Historical options and selected Phase 3 design

1. **Deterministic namespace UUID**：先给每个 lexical entry 分配持久不可变 source key，再用版本固定的 namespace + key 算 UUIDv5。不能直接 hash 可修改 expression/reading。需旧随机 UUID → canonical UUID 的 alias 与 progress/log 迁移，不能直接换 PK。
2. **Immutable source-key identity**：资源加入永久 lexical key，canonical identity 使用该 key；record UUID 保持本地实体身份。需要跨平台 key validation、同义/多义/跨等级建模和已有记录回填策略。
3. **Shared canonical ID manifest**：维护含永久 entry key 与 canonical UUID 的共享 manifest；Mac/Windows 共读，旧 UUID 通过 alias 映射保留历史。需要 manifest 修订、拆分/合并词义、资源升级和冲突处理规则。

Phase 3 selects shared canonical manifest + immutable source keys + UUID v5 in one fixed namespace. Local IDs are independent random UUID v4 on Windows and existing random UUIDs on Mac. All 10,609 entries, including ten cross-book duplicate pairs, are preserved. The ledger reserves old keys/IDs; retirements do not reuse them. UUID representation and lexical canonical identity remain distinct concepts.

Future Mac V4 migration must preflight exact book/expression/reading matches and reviewed unambiguous aliases, leave ambiguous/edited records canonicalID nil with diagnostics, and preserve local word/book/progress/log IDs, relationships, favorite, archive and history. Legacy local UUID aliases are diagnostic/migration aids, not cloud lexical IDs. See shared README for the complete plan.

## Internal SRS state encoding

**Presentation status != Persisted SRS state**。

| TEXT raw | Meaning | macOS presentation grouping |
|---|---|---|
| new | 尚未正式学习 | 未学习（无 progress 也可展示此状态） |
| learning | 初学短期状态 | 复习中 |
| relearning | 遗忘后重学 | 复习中 |
| review | 正式复习状态 | 复习中 |
| suspended | 熟练/暂停进入 due queue | 已熟练 |

不能把三种中文 presentation 字符串替代五种存储值。Windows CHECK 和 Rust enum 保留全部 raw values，拒绝未知值；当前 Swift getter 对未知值 fallback new，未来 adapter 应显式报错/quarantine，不静默改变语义。

`StudyDuePolicy` 对 learning/relearning 使用 `dueAt <= now`，review 使用当前 Calendar 的 day comparison，new/suspended 不 due。`due_progress(instant, review_day_end_exclusive)` 接收 caller 计算的本地当天结束 exclusive UTC instant；review 的条件为 dueAt < end，避免错误地把全部状态都按 UTC 当前瞬间筛选。Phase 2 不计算 timezone/day boundary，不构建 study queue，不实现 scheduler。

## Rating encoding and mastery behavior

真实 `ReviewRating` raw values 是 **again, hard, good, easy**，存 TEXT，不存 ordinal，也不存 `Mastered`。

- **Formal rating / manual Mastered on formal card**：StudySession 创建 ReviewLog，保存实际 rating。当前 DefaultReviewScheduler 的 easy 分支为 masteredResult：progress suspended、interval 0、due now。UI 的「熟练」对应 formal easy 的呈现，不是新的 raw case。
- **Automatic Mastery**：AutoMasteryPolicy 检查当前 review interval 60、最近正式 good、此次 good 等条件。满足时进度转 suspended，但正式日志 rating 仍为 good，nextState 可为 suspended。不能把该事件改记 easy。
- **Reinforcement Mastered override**：强化阶段 easy 是显式覆盖当前 progress 为 suspended/interval 0/due now；不新建第二份正式日志，不改写原正式 rating/nextState/due。其他强化评分属于 session 行为。
- **Reset**：WordbookService 的 reset 清除该词日志并重置进度，需 UI 确认。Windows Phase 2 只有未暴露给 IPC 的 scoped delete_logs_for_word，不建立 reset UI。

实际源码优先于旧调度说明；本阶段未修改 Mac scheduler，Windows 未实现任何以上行为。

## ReviewLog semantics

正式评分追加一条事件，记录当时状态、interval、due 和实际 rating。因此未来 formal history 适合事件式 append + UUID deduplication。但当前 StudySessionViewModel 在收到 SpellingSession 结果后会补充同一日志的 typed/expected answer、direction、错误集合与 reading/spelling counters（repeatedWrongCount 字段另行保留）；Backup overwriteByID 是另一修改通道；reset 和级联删除可以移除日志。

Windows repository 的 insert 是普通 INSERT（重复 PK 失败），query 按 reviewed_at DESC、id 排序，删除仅按一个 word_id。没有 INSERT OR REPLACE、无日志 upsert、无同步删除传播。未来需要区分正式事件核心、可补充元数据、删除/reset tombstone 与冲突版本；不能只把本地 delete 当作云端删除协议。

## Relationships, constraints and repository semantics

- word_books 1 → vocabulary_words 0..many；word 的 book 可空，有值 FK 必须存在。
- vocabulary_words 1 → learning_progress 0..1，word_id NOT NULL UNIQUE；progress 的 id 和 word ownership 不变。
- vocabulary_words 1 → review_logs 0..many，word_id NOT NULL。
- FK 全部 ON DELETE CASCADE 对应 Mac 父对象 cascade；每个 connection 都显式 PRAGMA foreign_keys = ON。Phase 2 不暴露删除书/词的命令，未来确认与 tombstone 设计须先完成。
- 四表 STRICT；UUID PK/关系格式检查；Bool 限 0/1；counter 非负；state/rating 封闭 CHECK；tags 为有效 JSON array，Rust 再校验 Vec<String>。error_types 由 typed repository 编码/读取，未知 raw 返回错误。
- Scalar 非可空字符串可为空；Backup 对 book name/japanese/kana/meaning 的非空预检是更高层规则，Schema 2 manifest importer 已校验 lexical required fields；历史 Schema 1 本身没有导入 validation。
- 不加 japanese+kana UNIQUE，不以表内容推定 lexical identity；各表 PK 不施加跨表 UUID UNIQUE（Backup 预检更严格）。
- Book/word/progress 显式 upsert 按同一个 id 修改字段，保留 created_at。不比较 updated_at，不执行 last-write-wins，不自动发明 ID；progress 同 ID 换 word 被拒绝，同 word 第二 progress 被 UNIQUE 拒绝。
- 索引：words_by_book(word_book_id)，progress_due(due_at) 对五状态中三种 due 状态的 partial index，logs_by_word_date(word_id, reviewed_at DESC, id)；主键/UNIQUE 已支持 ID 和 progress-by-word 查询。

## Persistent encodings

### Date encoding (fixed for Windows Schema 1)

**SQLite INTEGER，signed 64-bit Unix epoch microseconds UTC**，epoch 为 1970-01-01T00:00:00Z，1 秒 = 1,000,000 units。`Timestamp(i64)` 不使用 locale text。负数合法，例如 -1 是 epoch 前 1μs；null 表示 absence。

未来 Swift adapter 应以 `Date.timeIntervalSince1970 * 1_000_000` 转换，检查 finite 和 i64 范围，再以 nearest / ties away from zero 量化为整数；反向以 μs / 1_000_000 构建 Date。该 adapter **尚未实现**。INTEGER 对选定 μs domain 的 Rust/SQLite 往返精确；Swift Date 的浮点 submicrosecond 精度不能承诺逐 bit 无损（正常范围会有量化/浮点误差）。未来 PostgreSQL 的微秒 timestamp 可映射此精度，但网络 JSON/JavaScript Number 的安全整数范围必须另定，不能把任意 i64 直接作为 JS Number。

UTC 编码不定义用户时区或「一天」的调度含义。due day 判断使用 caller calendar。不能把 Swift referenceDate 2001 epoch 与 Unix 1970 混用。Backup 的 ISO8601 编码是另一 representation，现有默认输出不保证保留全部 subseconds；不声称 Backup 已是无损时间 sync protocol。

### UUID encoding

**TEXT canonical lowercase hyphenated 36 字符**：xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx。Rust Id 从合法 UUID 输入解析后按 canonical lower 写入；SQL CHECK 与 FromSql 拒绝非 canonical 持久化表示。无 BLOB / uppercase 混存。

这是 record UUID representation；canonical IDs now come from the checked-in manifest. Current Mac random UUID still is not cross-install lexical identity; Mac mapping remains unimplemented.

### Boolean encoding

**INTEGER 0 / 1**，Rust 对外 bool，SQL CHECK 拒绝其他整数，STRICT 拒绝不兼容类型。null 不代表 false；两个 loanword flags 在有效 V3 实体中均为非空。

### Enum and array encoding

SRS states / rating 使用上述稳定 TEXT raw 值；不依赖 enum ordinal。error_types 采用 Mac sorted raw values joined by `;`（空列表为空串），Rust 明确支持五种 ReviewErrorType；tags 使用 JSON 字符串数组保存顺序和内容。questionDirectionRawValue 可空开放字符串，以免未来 raw 扩展被误读为另一方向。

## Backup V3 audit

`KotobaBackupService.schemaVersion = 3`。Payload 包含 schemaVersion / exportedAt / appVersion，以及 wordBooks / vocabularyWords / learningProgress / reviewLogs 四数组；每实体输出 UUID id，wordBookID / wordID 输出关系 UUID，不序列化 SwiftData 对象地址。

JSONEncoder `.prettyPrinted` + `.sortedKeys`、date `.iso8601`；UUID 使用 Codable 字符串（未来 adapter canonicalize）。State、rating、errorTypes Codable raw 字符串；tags 数组；questionDirection raw optional string。V3 词源 term/code optional，DTO 两个 bool 也 optional 以兼容旧文件，restore 的 nil flags → false。其他 optional 包括 lastReviewedAt、typedAnswer、expectedAnswer 和 relation ID。

Decode 支持 legacy V1 normalization 和 V2/V3 DTO；future version 拒绝。不能从 backup JSON 版本号推导 SQLite schema version。

Restore/merge 根据模式使用时间较新内容、skip duplicates 或 overwriteByID；书/词/progress 以 updatedAt 比较，logs 不用不存在的 updatedAt，在非 overwrite 模式保留既有同 ID log。overwriteByID 可以替换现有 log 内容。不无条件删掉已有 store。

预检包含：同实体 duplicate UUID、cross-entity ID conflicts、必要名称/表达/读音/释义、非负 counters、有效关联、一个词最多一个 progress。检查 effective graph（含既有与导入记录）；孤立 wordBookID/wordID 或缺失所需关联被拒绝。先完整预检后 apply/save，失败 context.rollback。Importer 使用独立 context 和并发互斥协调，仍然是本地 restore，不是网络冲突协议。

**Backup schema != Sync schema**：缺少账户范围、设备身份、词条 canonical alias、delete tombstone、revision/checkpoint、并发评分合并等；ISO8601 精度也需单独约定。这里只复用已明确的实体/raw semantics，不实现 Windows backup reader。

## Windows Schema 2 lifecycle

使用 `rusqlite 0.40.2` + **bundled**（libsqlite3-sys 0.38.2，bundled SQLite 3.53.2）；当前稳定版本经 docs.rs 与 Cargo 解析确认。Tauri 2 / Rust 1.99 以本地编译和 Windows MSVC CI 验证兼容性，锁文件固定解析结果。SQLite 编入原生程序，不要求另装 SQLite DLL。

Tauri `app.path().app_data_dir()` 取得目录，再 mkdir/open `kotoba.sqlite3`。当前 identifier `com.fumi.kotoba.windows`；macOS Tauri 使用自身 OS app-data 目录，与原生 `com.fumi.Kotoba` SwiftData store 分离。Windows 使用 Tauri 的 OS app-data 位置，不从 repository/cwd/exe dir 推导，不 hard-code 用户路径。

`Database` 负责 open、5 秒 busy timeout、foreign_keys、migration、repository。单连接在 Tauri managed Mutex 中。`lib.rs` 负责 setup / commands；db/{models,migrations,repository,builtin,reads,mod}.rs 与两个历史 SQL migrations 分离。统一 DatabaseError 传播 SQLite / IO / encoding / schema / migration 错误；不 unwrap、expect、自动删除或 reset。

**PRAGMA user_version = 2**。Migration plan 保留原始 migration 1，新增真实 migration 2；IMMEDIATE transaction 内读取 version、依次应用 pending migration、更新 marker 并提交。失败 rollback DDL / data / marker，绝不 reset。真实 Schema 1 文件迁移测试保留四表全部旧字段、UUID 与关系；失败的 migration 2 测试保留 version 1、旧列和旧记录。重复 open 不重复迁移，未知高版本拒绝，必要 columns 缺失报错。此验证并非对任意外部篡改 schema 的完整 fingerprint/constraint 审计。

当前不配置 WAL/同步 tuning、加密、备份或跨进程 sync。测试使用 in-memory / tempfile，无生产路径依赖，文件 handles drop 后由 tempfile 清理。生产从不自动清空已有 DB。

`database_info` 返回 schemaVersion、manifestVersion、display-safe `app-data/kotoba.sqlite3` 描述与四表 counts；无用户绝对路径，无 arbitrary SQL。Svelte 通过 typed invoke 展示数量和基础搜索，不暴露 repository mutation IPC。

## Future sync considerations, compatibility risks and open questions

- canonical built-in identity 已由 manifest 建立；仍需设计旧 UUID aliases、资源修订/拆分/合并及用户自建词 identity。用户词的新增/跨设备重复与 owner 概念仅预留，未实现。
- Progress 是 mutable snapshot，formal logs 更接近事件；多设备独立评分不能靠简单 counter 相加或 updatedAt LWW 证明调度正确。是否 event replay、谁能改 suspended、如何 reset 都待决定。
- Mac spelling enrichment 修改既有 log；需要日志 revision/finalization 或独立 enrichment event，未决定 schema 改动。
- 当前无 tombstone、account/device/revision metadata；archive 不等于 delete；reset 的传播与 cascade 的跨设备语义未定义。可能外部 side table 足够，可能未来 V4，需要正式方案后评估。
- 微秒量化、Backup 秒级日期、JS i64 边界、DST/calendar/timezone 与 unknown raw value 的处理需 adapter contract tests。
- Mac optional relationships / Windows complete progress/log graph、Backup cross-entity UUID checks / SQL per-table PK、字符串非空、源词合法性规则有显式边界，不是完成了互导。
- SQL upsert 是显式本地操作，不是 import merge 或同步冲突策略。数据库初始化报错不删除用户数据。
- Windows 已导入 10,609 条，Mac canonical mapping 尚未实现；没有 SQLite → SwiftData/Backup 转换器；Windows installer 有 CI build evidence，物理 Windows UI/runtime 与签名仍未验证/配置。

## Explicit non-goals

不改 macOS SwiftData V1/V2/V3、Backup V3、UUID、seedVersion、ReviewScheduler、StudySession、ReviewLog 或 UI；不建立 V4。无 Supabase/Auth/network sync、Windows SRS/study/wordbook/statistics/spelling/import UI。Phase 3 adds only canonical manifest/seed/read diagnostics; it does not implement Mac mapping or cloud sync.

## Phase 3 Schema 2 additions and importer ownership

Migration 2 adds WordBook and VocabularyWord `canonical_id TEXT UUID?`, `canonical_key TEXT?` as paired nullable fields, partial UNIQUE indices and immutable-identity triggers. Existing Schema 1 SQL/rows are preserved. Local id/createdAt semantics stay unchanged. Source built-ins require canonical identity in importer/read service; future custom content may have null. The current Mac model has no equivalent canonical field yet. Both canonical fields are persisted sync candidates and immutable after assignment.

`built_in_content` is separate content metadata: manifest_version, format_version, namespace_uuid, manifest_fingerprint and identity_fingerprint. It is not SwiftData schema version, not PRAGMA user_version and not a sync checkpoint. Content/identity fingerprints use UUID v5 over deterministic serialized data, not security signatures.

One validated transaction imports five books and 10,609 entries using prepared statements. Content updates retain local IDs, creation times, isFavorite, isArchived, all progress and all logs. Only lexical/source fields and book association may update; updatedAt changes only with actual lexical updates. Missing manifest entries are retained with existing flags/history; future archive/tombstone policy remains undecided. No progress/log is created during seed.

Typed Rust reads expose book summaries, get_word by local id, canonical lookup internally, paginated lists and literal substring search. Limits are 1..100, offsets unsigned, search capped at 200 characters; empty search returns no results. All text is parameterized and LIKE escapes percent/underscore/backslash. Frontend IPC never sends all 10,609 rows or arbitrary SQL.

Manifest and ledger are compile-time embedded. Actual release EXE probe runs from empty temp cwd in CI, and native tempfile tests verify schema 2/import/counts/reopen/idempotency. Diagnostics show Schema 2 / built-in count / per-book counts and a small search form; no study UI or scheduler.
