import SwiftUI

enum KanaChartLayoutPolicy {
    static let rowLabelWidth: CGFloat = 44
    static let cellSpacing: CGFloat = 6

    static func horizontalPadding(for availableWidth: CGFloat) -> CGFloat {
        availableWidth < 520 ? 16 : 24
    }

    static func estimatedCellWidth(for availableWidth: CGFloat, columnCount: Int) -> CGFloat {
        guard columnCount > 0 else { return 0 }
        let padding = horizontalPadding(for: availableWidth) * 2
        let spacing = cellSpacing * CGFloat(columnCount)
        return max(0, (availableWidth - padding - rowLabelWidth - spacing) / CGFloat(columnCount))
    }
}

struct KanaChartView: View {
    @State private var script: KanaScript = .hiragana

    var body: some View {
        PageScaffold(title: "五十音图", subtitle: "平假名与片假名参考表。") {
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Picker("文字", selection: $script) {
                            ForEach(KanaScript.allCases) { item in
                                Text(item.rawValue).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 320)

                        KanaGridSection(
                            title: "清音",
                            columnLabels: KanaChartData.mainColumnLabels,
                            rows: KanaChartData.seionRows,
                            script: script
                        )

                        KanaGridSection(
                            title: "浊音・半浊音",
                            columnLabels: KanaChartData.mainColumnLabels,
                            rows: KanaChartData.dakuonHandakuonRows,
                            script: script
                        )

                        KanaGridSection(
                            title: "拗音",
                            columnLabels: KanaChartData.yoonColumnLabels,
                            rows: KanaChartData.yoonRows,
                            script: script
                        )

                        VStack(alignment: .leading, spacing: 5) {
                            Text("ゐ／ヰ（wi）、ゑ／ヱ（we）是历史假名，现代日语通常不使用。")
                            Text("「は」「へ」「を」作助词时通常分别读作 wa、e、o。")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, KanaChartLayoutPolicy.horizontalPadding(for: proxy.size.width))
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct KanaGridSection: View {
    let title: String
    let columnLabels: [String]
    let rows: [KanaRow]
    let script: KanaScript

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.semibold))

            Grid(alignment: .center, horizontalSpacing: KanaChartLayoutPolicy.cellSpacing, verticalSpacing: 6) {
                GridRow {
                    Color.clear
                        .frame(width: KanaChartLayoutPolicy.rowLabelWidth, height: 1)
                        .accessibilityHidden(true)
                    ForEach(columnLabels, id: \.self) { label in
                        Text(label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        Text(row.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: KanaChartLayoutPolicy.rowLabelWidth, alignment: .trailing)
                            .accessibilityHidden(true)

                        ForEach(row.entries.indices, id: \.self) { index in
                            if let entry = row.entries[index] {
                                KanaCell(entry: entry, script: script)
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity, minHeight: 58)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct KanaCell: View {
    let entry: KanaEntry
    let script: KanaScript

    var body: some View {
        VStack(spacing: 2) {
            Text(entry.glyph(for: script))
                .font(.system(size: 25, weight: .medium))
            Text(entry.romaji)
                .font(.caption2)
        }
        .foregroundStyle(entry.isHistorical ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 7))
        .help(entry.isHistorical ? "历史假名，现代日语通常不使用" : entry.accessibilityLabel(for: script))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.accessibilityLabel(for: script))
    }
}

#Preview {
    KanaChartView()
        .frame(width: 720, height: 560)
}
