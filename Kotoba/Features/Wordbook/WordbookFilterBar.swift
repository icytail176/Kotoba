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
            HStack(spacing: 10) {
                TextField("搜索单词、假名或中文释义", text: $filters.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 220)

                Toggle("仅收藏", isOn: $filters.favoritesOnly)
                    .toggleStyle(.checkbox)

                Spacer()

                Button(action: onImport) {
                    Label("导入 CSV", systemImage: "square.and.arrow.down")
                }

                Button(action: onAdd) {
                    Label("新增单词", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 10) {
                filterPicker("JLPT", selection: $filters.jlptLevel, values: optionSets.jlptLevels)
                filterPicker("词性", selection: $filters.partOfSpeech, values: optionSets.partsOfSpeech)
                filterPicker("标签", selection: $filters.tag, values: optionSets.tags)

                Picker("学习状态", selection: $filters.learningState) {
                    Text("全部").tag(WordbookFilterValue.all.rawValue)
                    ForEach(optionSets.learningStates) { state in
                        Text(state.displayName).tag(state.rawValue)
                    }
                }
                .frame(maxWidth: 160)

                Spacer()

                Button("清除筛选", action: onClear)
                    .disabled(!isFiltering)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 12)
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
        .frame(maxWidth: 150)
    }
}

#Preview {
    WordbookFilterBar(
        filters: .constant(WordbookFilters()),
        optionSets: WordbookOptionSets(
            jlptLevels: ["N5", "N4"],
            partsOfSpeech: ["名词", "动词"],
            tags: ["学校", "生活"],
            learningStates: [.new, .review]
        ),
        isFiltering: false,
        onClear: {},
        onAdd: {},
        onImport: {}
    )
    .frame(width: 860)
}
