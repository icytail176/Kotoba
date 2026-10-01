//
//  WordbookFilterBar.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import SwiftUI

struct WordbookFilterBar: View {
    @Binding var filters: WordbookFilters
    let optionSets: WordbookOptionSets
    let isFiltering: Bool
    let onClear: () -> Void
    let onAdd: () -> Void
    let onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer()
                actionControls
            }

            ViewThatFits(in: .horizontal) {
                filterControls

                VStack(alignment: .leading, spacing: 10) {
                    wordBookAndLevelFilters
                    metadataFilters
                    Button("清除筛选", action: onClear)
                        .disabled(!isFiltering)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var actionControls: some View {
        HStack(spacing: 10) {
            Button(action: onImport) {
                Label("导入 CSV", systemImage: "square.and.arrow.down")
            }

            Button(action: onAdd) {
                Label("新增单词", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var filterControls: some View {
        HStack(spacing: 10) {
            wordBookAndLevelFilters
            metadataFilters

            Spacer(minLength: 8)

            Button("清除筛选", action: onClear)
                .disabled(!isFiltering)
        }
    }

    private var wordBookAndLevelFilters: some View {
        HStack(spacing: 10) {
            Picker("词书", selection: $filters.wordBookID) {
                Text("当前词书").tag(WordbookFilters.currentWordBookValue)
                Text("全部词书").tag(WordbookFilterValue.all.rawValue)
                ForEach(optionSets.wordBooks) { wordBook in
                    Text(wordBook.name).tag(wordBook.id.uuidString)
                }
            }
            .frame(minWidth: 110, idealWidth: 130, maxWidth: 170)

            filterPicker("JLPT", selection: $filters.jlptLevel, values: optionSets.jlptLevels)
        }
    }

    private var metadataFilters: some View {
        HStack(spacing: 10) {
            filterPicker("词性", selection: $filters.partOfSpeech, values: optionSets.partsOfSpeech)
            filterPicker("标签", selection: $filters.tag, values: optionSets.tags)

            Picker("状态", selection: $filters.status) {
                ForEach(WordbookStatusFilter.allCases) { status in
                    Text(status.displayName).tag(status)
                }
            }
            .frame(minWidth: 100, idealWidth: 120, maxWidth: 140)

            Picker("排序", selection: $filters.sort) {
                ForEach(WordbookSortOption.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .frame(minWidth: 100, idealWidth: 120, maxWidth: 140)
        }
    }

    private func filterPicker(
        _ title: String,
        selection: Binding<String>,
        values: [String]
    ) -> some View {
        Picker(title, selection: selection) {
            Text("全部").tag(WordbookFilterValue.all.rawValue)
            ForEach(values, id: \.self) { value in
                Text(value).tag(value)
            }
        }
        .frame(minWidth: 82, idealWidth: 96, maxWidth: 120)
    }
}

#Preview {
    WordbookFilterBarPreview()
        .frame(width: 860)
}

private struct WordbookFilterBarPreview: View {
    var body: some View {
        WordbookFilterBar(
            filters: .constant(WordbookFilters()),
            optionSets: WordbookOptionSets(
                wordBooks: [WordBookOption(id: UUID(), name: "示例词书")],
                jlptLevels: ["N5", "N4"],
                partsOfSpeech: ["名词", "动词"],
                tags: ["学校", "生活"]
            ),
            isFiltering: false,
            onClear: {},
            onAdd: {},
            onImport: {}
        )
    }
}
