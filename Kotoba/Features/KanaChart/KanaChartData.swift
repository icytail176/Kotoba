import Foundation

enum KanaScript: String, CaseIterable, Identifiable {
    case hiragana = "平假名"
    case katakana = "片假名"

    var id: String { rawValue }
}

struct KanaEntry: Equatable, Sendable {
    let hiragana: String
    let katakana: String
    let romaji: String
    let isHistorical: Bool

    init(
        hiragana: String,
        katakana: String,
        romaji: String,
        isHistorical: Bool = false
    ) {
        self.hiragana = hiragana
        self.katakana = katakana
        self.romaji = romaji
        self.isHistorical = isHistorical
    }

    func glyph(for script: KanaScript) -> String {
        switch script {
        case .hiragana: hiragana
        case .katakana: katakana
        }
    }

    func accessibilityLabel(for script: KanaScript) -> String {
        let base = "\(glyph(for: script))，\(romaji)"
        return isHistorical ? "\(base)，历史假名，现代日语通常不使用" : base
    }
}

struct KanaRow: Equatable, Sendable {
    let label: String
    let entries: [KanaEntry?]
}

enum KanaChartData {
    static let mainColumnLabels = ["あ段", "い段", "う段", "え段", "お段"]
    static let yoonColumnLabels = ["ゃ段", "ゅ段", "ょ段"]

    static let seionRows: [KanaRow] = [
        row("あ行", [entry("あ", "ア", "a"), entry("い", "イ", "i"), entry("う", "ウ", "u"), entry("え", "エ", "e"), entry("お", "オ", "o")]),
        row("か行", [entry("か", "カ", "ka"), entry("き", "キ", "ki"), entry("く", "ク", "ku"), entry("け", "ケ", "ke"), entry("こ", "コ", "ko")]),
        row("さ行", [entry("さ", "サ", "sa"), entry("し", "シ", "shi"), entry("す", "ス", "su"), entry("せ", "セ", "se"), entry("そ", "ソ", "so")]),
        row("た行", [entry("た", "タ", "ta"), entry("ち", "チ", "chi"), entry("つ", "ツ", "tsu"), entry("て", "テ", "te"), entry("と", "ト", "to")]),
        row("な行", [entry("な", "ナ", "na"), entry("に", "ニ", "ni"), entry("ぬ", "ヌ", "nu"), entry("ね", "ネ", "ne"), entry("の", "ノ", "no")]),
        row("は行", [entry("は", "ハ", "ha"), entry("ひ", "ヒ", "hi"), entry("ふ", "フ", "fu"), entry("へ", "ヘ", "he"), entry("ほ", "ホ", "ho")]),
        row("ま行", [entry("ま", "マ", "ma"), entry("み", "ミ", "mi"), entry("む", "ム", "mu"), entry("め", "メ", "me"), entry("も", "モ", "mo")]),
        row("や行", [entry("や", "ヤ", "ya"), nil, entry("ゆ", "ユ", "yu"), nil, entry("よ", "ヨ", "yo")]),
        row("ら行", [entry("ら", "ラ", "ra"), entry("り", "リ", "ri"), entry("る", "ル", "ru"), entry("れ", "レ", "re"), entry("ろ", "ロ", "ro")]),
        row("わ行", [entry("わ", "ワ", "wa"), entry("ゐ", "ヰ", "wi", historical: true), nil, entry("ゑ", "ヱ", "we", historical: true), entry("を", "ヲ", "wo")]),
        row("ん", [entry("ん", "ン", "n"), nil, nil, nil, nil])
    ]

    static let dakuonHandakuonRows: [KanaRow] = [
        row("が行", [entry("が", "ガ", "ga"), entry("ぎ", "ギ", "gi"), entry("ぐ", "グ", "gu"), entry("げ", "ゲ", "ge"), entry("ご", "ゴ", "go")]),
        row("ざ行", [entry("ざ", "ザ", "za"), entry("じ", "ジ", "ji"), entry("ず", "ズ", "zu"), entry("ぜ", "ゼ", "ze"), entry("ぞ", "ゾ", "zo")]),
        row("だ行", [entry("だ", "ダ", "da"), entry("ぢ", "ヂ", "ji"), entry("づ", "ヅ", "zu"), entry("で", "デ", "de"), entry("ど", "ド", "do")]),
        row("ば行", [entry("ば", "バ", "ba"), entry("び", "ビ", "bi"), entry("ぶ", "ブ", "bu"), entry("べ", "ベ", "be"), entry("ぼ", "ボ", "bo")]),
        row("ぱ行", [entry("ぱ", "パ", "pa"), entry("ぴ", "ピ", "pi"), entry("ぷ", "プ", "pu"), entry("ぺ", "ペ", "pe"), entry("ぽ", "ポ", "po")])
    ]

    static let yoonRows: [KanaRow] = [
        yoonRow("きゃ行", "きゃ", "キャ", "kya", "きゅ", "キュ", "kyu", "きょ", "キョ", "kyo"),
        yoonRow("しゃ行", "しゃ", "シャ", "sha", "しゅ", "シュ", "shu", "しょ", "ショ", "sho"),
        yoonRow("ちゃ行", "ちゃ", "チャ", "cha", "ちゅ", "チュ", "chu", "ちょ", "チョ", "cho"),
        yoonRow("にゃ行", "にゃ", "ニャ", "nya", "にゅ", "ニュ", "nyu", "にょ", "ニョ", "nyo"),
        yoonRow("ひゃ行", "ひゃ", "ヒャ", "hya", "ひゅ", "ヒュ", "hyu", "ひょ", "ヒョ", "hyo"),
        yoonRow("みゃ行", "みゃ", "ミャ", "mya", "みゅ", "ミュ", "myu", "みょ", "ミョ", "myo"),
        yoonRow("りゃ行", "りゃ", "リャ", "rya", "りゅ", "リュ", "ryu", "りょ", "リョ", "ryo"),
        yoonRow("ぎゃ行", "ぎゃ", "ギャ", "gya", "ぎゅ", "ギュ", "gyu", "ぎょ", "ギョ", "gyo"),
        yoonRow("じゃ行", "じゃ", "ジャ", "ja", "じゅ", "ジュ", "ju", "じょ", "ジョ", "jo"),
        yoonRow("びゃ行", "びゃ", "ビャ", "bya", "びゅ", "ビュ", "byu", "びょ", "ビョ", "byo"),
        yoonRow("ぴゃ行", "ぴゃ", "ピャ", "pya", "ぴゅ", "ピュ", "pyu", "ぴょ", "ピョ", "pyo")
    ]

    private static func entry(
        _ hiragana: String,
        _ katakana: String,
        _ romaji: String,
        historical: Bool = false
    ) -> KanaEntry {
        KanaEntry(hiragana: hiragana, katakana: katakana, romaji: romaji, isHistorical: historical)
    }

    private static func row(_ label: String, _ entries: [KanaEntry?]) -> KanaRow {
        KanaRow(label: label, entries: entries)
    }

    private static func yoonRow(
        _ label: String,
        _ h1: String, _ k1: String, _ r1: String,
        _ h2: String, _ k2: String, _ r2: String,
        _ h3: String, _ k3: String, _ r3: String
    ) -> KanaRow {
        row(label, [entry(h1, k1, r1), entry(h2, k2, r2), entry(h3, k3, r3)])
    }
}
