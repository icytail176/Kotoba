import SwiftUI

struct KeyboardShortcutReference {
    struct Section: Identifiable {
        let title: String
        let items: [Item]
        var id: String { title }
    }

    struct Item: Identifiable {
        let action: String
        let keys: String
        var id: String { "\(action)-\(keys)" }
    }

    static let sections: [Section] = [
        Section(title: "今日学习", items: [
            Item(action: "学习新词", keys: "L"),
            Item(action: "复习旧词", keys: "R")
        ]),
        Section(title: "学习卡片", items: [
            Item(action: "显示答案", keys: "Space"),
            Item(action: "忘记 / 模糊 / 认识", keys: "1 / 2 / 3"),
            Item(action: "熟练", keys: "Delete / Backspace"),
            Item(action: "切换卡片页", keys: "← / →"),
            Item(action: "收藏或取消收藏", keys: "F"),
            Item(action: "退出本组", keys: "Escape")
        ]),
        Section(title: "拼写", items: [
            Item(action: "提交 / 下一题", keys: "Enter"),
            Item(action: "显示假名提示（第一轮）", keys: "⌘⇧H")
        ]),
        Section(title: "学习小结", items: [
            Item(action: "返回首页", keys: "Enter")
        ]),
        Section(title: "搜索", items: [
            Item(action: "聚焦单词搜索", keys: "⌘F"),
            Item(action: "选择建议", keys: "↑ / ↓"),
            Item(action: "打开建议", keys: "Enter"),
            Item(action: "关闭建议", keys: "Escape")
        ])
    ]
}

struct KeyboardShortcutHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("快捷键帮助")
                        .font(.title2.weight(.semibold))

                    ForEach(KeyboardShortcutReference.sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title).font(.headline)
                            ForEach(section.items) { item in
                                LabeledContent(item.action) {
                                    Text(item.keys)
                                        .font(.callout.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }

            Divider()
            HStack {
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
        }
        .frame(minWidth: 360, idealWidth: 480, maxWidth: 560, minHeight: 360, idealHeight: 540, maxHeight: 680)
    }
}
