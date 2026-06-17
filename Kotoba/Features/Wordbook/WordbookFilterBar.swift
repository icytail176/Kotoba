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
    let searchFieldFocus: FocusState<Bool>.Binding
    let onClear: () -> Void
    let onAdd: () -> Void
    let onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                TextField("搜索单词、假名或中文释义", text: $filters.searchText)
                    .textFieldStyle(.roundedBorder)
                    .focused(searchFieldFocus)
                    .frame(minWidth: 160, maxWidth: .infinity)

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
                Picker("词书", selection: $filters.wordBookID) {
                    Text("当前词书").tag(WordbookFilters.currentWordBookValue)
                    Text("全部词书").tag(WordbookFilterValue.all.rawValue)
                    ForEach(optionSets.wordBooks) { wordBook in
                        Text(wordBook.name).tag(wordBook.id.uuidString)
                    }
                }
                .frame(minWidth: 120, maxWidth: 180)

                filterPicker("JLPT", selection: $filters.jlptLevel, values: optionSets.jlptLevels)
                filterPicker("词性", selection: $filters.partOfSpeech, values: optionSets.partsOfSpeech)
                filterPicker("标签", selection: $filters.tag, values: optionSets.tags)

                Picker("学习状态", selection: $filters.learningState) {
                    Text("全部").tag(WordbookFilterValue.all.rawValue)
                    ForEach(optionSets.learningStates) { state in
                        Text(state.displayName).tag(state.rawValue)
                    }
                }
                .frame(minWidth: 110, maxWidth: 140)

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
        .frame(minWidth: 90, maxWidth: 130)
    }
}

#Preview {
    WordbookFilterBarPreview()
        .frame(width: 860)
}

private struct WordbookFilterBarPreview: View {
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        WordbookFilterBar(
            filters: .constant(WordbookFilters()),
            optionSets: WordbookOptionSets(
                wordBooks: [WordBookOption(id: UUID(), name: "示例词书")],
                jlptLevels: ["N5", "N4"],
                partsOfSpeech: ["名词", "动词"],
                tags: ["学校", "生活"],
                learningStates: [.new, .review]
            ),
            isFiltering: false,
            searchFieldFocus: $isSearchFieldFocused,
            onClear: {},
            onAdd: {},
            onImport: {}
        )
    }
}
