# Kotoba

Kotoba は、中国語話者の JLPT 語彙学習と復習に特化した macOS ネイティブアプリです。

## 概要

Kotoba は Swift、SwiftUI、SwiftData で開発されたローカルファーストの日本語単語学習アプリです。JLPT N5〜N1 の内蔵単語帳を使い、学習、復習、スペリング練習、進捗確認を一つのアプリで行えます。オンラインアカウントは必要ありません。

## 主な機能

### JLPT N5〜N1 単語帳

10,609 語を収録しています。

| 単語帳 | 収録語数 |
| --- | ---: |
| JLPT N5 | 802 |
| JLPT N4 | 755 |
| JLPT N3 | 1,817 |
| JLPT N2 | 3,206 |
| JLPT N1 | 4,029 |
| 合計 | 10,609 |

### SRS 学習・復習

カードの評価に応じて次回の復習をスケジュールします。評価は「忘れた」「あいまい」「わかる」「習得済み」の 4 段階です。

### Automatic Mastery

十分に安定した復習履歴を持つ単語を、自動的に「習得済み」として扱います。

### カード強化

正式なカード評価の後、同じ学習セッション内で追加の強化を行います。強化中の回答は、正式な復習記録やスケジュールを重複して更新しません。

### 2 段階のスペリング練習

- 中国語の意味や例文の文脈から、日本語の単語を入力します。必要に応じて仮名のヒントを表示できます。
- 日本語の単語を見て、読みを仮名で入力します。

誤答した単語は同じ段階の後半でもう一度出題されます。

### ローマ字

学習カードと単語詳細に、読みのローマ字表記を表示します。

### ピッチアクセント

内蔵データに対応するアクセント情報がある場合、学習カードと単語詳細にアクセント型を表示します。

### 外来語の語源

対応する外来語では、原語、言語、和製語、部分借用などの情報を表示します。

### 五十音図

平仮名と片仮名を切り替えながら、清音、濁音・半濁音、拗音を確認できます。歴史的仮名遣いの「ゐ／ヰ」「ゑ／ヱ」も区別して掲載しています。

### 単語詳細

読み、ローマ字、ピッチアクセント、外来語の語源、学習状態、復習予定、最近の復習履歴を確認できます。お気に入りの切り替え、活用形の確認、学習状態を未学習に戻す操作にも対応しています。

### 検索・フィルター・並べ替え

単語、読み、意味、外来語の原語、ローマ字を検索できます。単語帳、JLPT レベル、品詞、タグのほか、「すべて」「未学習」「復習中」「習得済み」「お気に入り」「苦手な単語」で絞り込めます。標準順、最近学習した順、次回復習順、忘却回数順で並べ替えられます。

### 学習進捗と復習履歴

進捗は「未学習」「復習中」「習得済み」の 3 区分で表示します。単語詳細では、その単語に限定した最近の正式な復習履歴を確認できます。

### 7 日間の復習予測

ホーム画面に、今後 7 日間の復習予定を表示します。

### 学習統計

7 日間または 30 日間の範囲で、正式評価数、新しく学習した単語数、手動・自動の習得数、スペリング初回正答率、日別学習量、評価分布、苦手な単語を確認できます。累計学習語数と連続学習日数も表示します。

### キーボード操作

主要な学習操作をキーボードで行えます。現在利用できるショートカットは、アプリ内の「?」ボタンから確認できます。

### CSV インポート・エクスポート

UTF-8 CSV の事前検証、プレビュー、行単位のエラー表示、重複処理に対応しています。単語帳は標準 CSV 形式で書き出せます。

### JSON バックアップ

JSON Backup V3 で、単語帳、単語、学習進捗、復習記録をバックアップおよび復元できます。インポート前の検証、重複データの処理方法の選択、失敗時のロールバックに対応しています。

## データとプライバシー

- 学習データは、この Mac 上の SwiftData ストアに保存されます。
- アカウント登録は不要です。
- 現行バージョンはクラウドデータベース、オンライン AI / LLM、オンライン辞書に依存しません。
- 現行のソースコードには、広告 SDK やトラッキング SDK は含まれていません。

## 動作環境

- macOS 26.5 以降

## ダウンロード

[GitHub Releases](https://github.com/icytail176/Kotoba/releases) から `Kotoba-0.2.1-macOS-local-signed.zip` をダウンロードしてください。GitHub が自動生成する Source code アーカイブには、実行可能なアプリは含まれていません。

## インストール

1. Releases から `Kotoba-0.2.1-macOS-local-signed.zip` をダウンロードします。
2. ZIP を展開します。
3. `Kotoba.app` を Applications フォルダへ移動します。
4. `Kotoba.app` を起動します。

このビルドはローカル署名されており、Apple の notarization は受けていません。初回起動時に macOS によって起動がブロックされた場合は、Finder で `Kotoba.app` を右クリックして「開く」を選び、確認ダイアログでもう一度「開く」を選択してください。必要に応じて「システム設定」→「プライバシーとセキュリティ」から「このまま開く」を選択できます。

Gatekeeper を無効にしたり、システム全体のセキュリティ設定を変更したりする必要はありません。

## 現在のバージョン

Kotoba 0.2.1 (Build 3)

## 開発情報

- Swift
- SwiftUI
- SwiftData
- Xcode 27
- macOS ネイティブアプリ

サードパーティーのランタイム依存関係はありません。

## ソースからのビルド

```bash
git clone git@github.com:icytail176/Kotoba.git
cd Kotoba
```

`Kotoba.xcodeproj` を Xcode 27 で開き、`Kotoba` スキームを選択して実行します。

コマンドラインからテストする場合:

```bash
xcodebuild test \
  -project Kotoba.xcodeproj \
  -scheme Kotoba \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

## サードパーティーデータと Attribution

### egg rolls / anki-jlpt-decks

内蔵 JLPT 単語帳、ピッチアクセントのタグ、外来語の原型フィールドは、[egg rolls / anki-jlpt-decks](https://github.com/5mdld/anki-jlpt-decks) のデータを整理・変更して使用しています。このデータは [Creative Commons Attribution-NonCommercial 4.0 International (CC BY-NC 4.0)](https://creativecommons.org/licenses/by-nc/4.0/) の下で提供されています。

### JMdict

外来語語源 sidecar の補足には、Electronic Dictionary Research and Development Group が提供する [JMdict](https://www.edrdg.org/jmdict/j_jmdict.html) のうち、単語と読みに明確に対応する `lsource` 情報のみを保守的に使用しています。JMdict は [Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)](https://www.edrdg.org/edrdg/licence.html) の下で提供されています。

生成方法と照合規則は `Scripts/generate_loanword_etymology.py`、詳細な声明は `Kotoba/Resources/JMdict_NOTICE.txt` にあります。第三者データを再利用する場合は、それぞれのライセンスと Attribution 要件を確認してください。

## ライセンス

このリポジトリには、現時点でソフトウェア本体を対象とする独立した `LICENSE` ファイルは含まれていません。上記の第三者データには、それぞれのライセンスが適用されます。それ以外のコードとプロジェクト資産の利用、変更、再配布には、リポジトリ所有者の許可が必要です。

---

# English

Kotoba is a native macOS app for Chinese-speaking learners studying and reviewing Japanese vocabulary for the JLPT.

## Overview

Kotoba is a local-first Japanese vocabulary app built with Swift, SwiftUI, and SwiftData. It brings together study, review, spelling practice, and progress tracking for its built-in JLPT N5–N1 wordbooks. No online account is required.

## Features

### JLPT N5–N1 Wordbooks

Kotoba includes 10,609 vocabulary entries.

| Wordbook | Entries |
| --- | ---: |
| JLPT N5 | 802 |
| JLPT N4 | 755 |
| JLPT N3 | 1,817 |
| JLPT N2 | 3,206 |
| JLPT N1 | 4,029 |
| Total | 10,609 |

### SRS Study and Review

Kotoba schedules the next review from one of four card ratings: Forgot, Unsure, Know, and Mastered.

### Automatic Mastery

Words with a sufficiently stable review history can be marked as mastered automatically.

### Card Reinforcement

After the formal card rating, Kotoba adds reinforcement within the same study session. Reinforcement answers do not create duplicate formal review records or reschedule the word.

### Two-Stage Spelling Practice

- Enter the Japanese word from its Chinese meaning or example context. A kana hint is available when needed.
- Enter the kana reading from the Japanese word.

Missed words return later in the same stage until answered correctly.

### Romaji

Study cards and word details show a romaji rendering of the reading.

### Pitch Accent

When supported by the bundled data, study cards and word details show the pitch-accent pattern.

### Loanword Etymology

Supported loanwords can show the source term, source language, wasei status, and partial-borrowing information.

### Kana Chart

The kana chart switches between hiragana and katakana and covers basic kana, voiced and semi-voiced kana, and yōon combinations. Historical kana such as ゐ / ヰ and ゑ / ヱ are identified separately.

### Word Details

Word details include the reading, romaji, pitch accent, loanword etymology, learning state, review schedule, and recent review history. You can also toggle favorites, inspect locally generated conjugations, or reset a word to the unlearned state.

### Search, Filters, and Sorting

Search covers the expression, reading, meaning, loanword source term, and romaji. Filter by wordbook, JLPT level, part of speech, tag, or the All, Unlearned, Reviewing, Mastered, Favorites, and Difficult categories. Sort by default order, most recently studied, next review, or lapse count.

### Learning Progress and Review History

Progress is summarized as Unlearned, Reviewing, or Mastered. Word details show recent formal review history scoped to the selected word.

### Seven-Day Review Forecast

The Home screen shows scheduled reviews for the next seven days.

### Learning Statistics

Choose a 7-day or 30-day range to inspect formal ratings, newly learned words, manual and automatic mastery, first-pass spelling accuracy, daily activity, rating distribution, and difficult words. Kotoba also shows total learned words and the current study streak.

### Keyboard Control

Core study actions are available from the keyboard. The in-app `?` button lists the currently supported shortcuts.

### CSV Import and Export

UTF-8 CSV import includes preflight validation, a preview, row-level error reporting, and duplicate handling. Wordbooks can be exported in the standard CSV format.

### JSON Backup

JSON Backup V3 can back up and restore wordbooks, vocabulary, learning progress, and review records. Imports support validation, duplicate-handling strategies, and rollback on failure.

## Data & Privacy

- Learning data is stored in a SwiftData store on your Mac.
- No account is required.
- The current version does not depend on a cloud database, online AI / LLM services, or an online dictionary.
- The current source does not include advertising or tracking SDKs.

## Requirements

- macOS 26.5 or later

## Download

Download `Kotoba-0.2.1-macOS-local-signed.zip` from [GitHub Releases](https://github.com/icytail176/Kotoba/releases). GitHub's automatically generated Source code archives do not contain the runnable app.

## Installation

1. Download `Kotoba-0.2.1-macOS-local-signed.zip` from Releases.
2. Extract the ZIP archive.
3. Move `Kotoba.app` to the Applications folder.
4. Launch `Kotoba.app`.

This build is locally signed and is not notarized by Apple. If macOS blocks the first launch, right-click `Kotoba.app` in Finder, choose Open, and then confirm Open in the dialog. If necessary, use Open Anyway under System Settings → Privacy & Security.

You do not need to disable Gatekeeper or change system-wide security settings.

## Current Version

Kotoba 0.2.1 (Build 3)

## Development

- Swift
- SwiftUI
- SwiftData
- Xcode 27
- Native macOS application

Kotoba has no third-party runtime dependencies.

## Building from Source

```bash
git clone git@github.com:icytail176/Kotoba.git
cd Kotoba
```

Open `Kotoba.xcodeproj` in Xcode 27, select the `Kotoba` scheme, and run the project.

To run the tests from the command line:

```bash
xcodebuild test \
  -project Kotoba.xcodeproj \
  -scheme Kotoba \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

## Third-Party Data & Attribution

### egg rolls / anki-jlpt-decks

The built-in JLPT wordbooks, pitch-accent tags, and loanword source-form fields are based on organized and modified data from [egg rolls / anki-jlpt-decks](https://github.com/5mdld/anki-jlpt-decks). That data is provided under the [Creative Commons Attribution-NonCommercial 4.0 International license (CC BY-NC 4.0)](https://creativecommons.org/licenses/by-nc/4.0/).

### JMdict

As a supplement to the loanword etymology sidecar, Kotoba conservatively uses only explicit `lsource` information from [JMdict](https://www.edrdg.org/jmdict/j_jmdict.html) that can be matched unambiguously by word and reading. JMdict is provided by the Electronic Dictionary Research and Development Group under the [Creative Commons Attribution-ShareAlike 4.0 International license (CC BY-SA 4.0)](https://www.edrdg.org/edrdg/licence.html).

The generator and matching rules are in `Scripts/generate_loanword_etymology.py`, and the full notice is preserved in `Kotoba/Resources/JMdict_NOTICE.txt`. Review the applicable license and attribution requirements before reusing third-party data.

## License

This repository currently does not include a standalone `LICENSE` file for the software itself. The third-party data described above remains subject to its respective license. Permission from the repository owner is required to use, modify, or redistribute the remaining code and project assets.
