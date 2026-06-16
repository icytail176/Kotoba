//
//  ContentView.swift
//  Kotoba
//
//  Created by Fumi on 2026/6/16.
//

import SwiftUI

struct ContentView: View {
    @State private var selection: AppSection? = .today

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("Kotoba")
        } detail: {
            detailView(for: selection ?? .today)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 600)
    }

    @ViewBuilder
    private func detailView(for section: AppSection) -> some View {
        switch section {
        case .today:
            TodayStudyView()
        case .wordbook:
            WordbookView()
        case .statistics:
            StatisticsView()
        case .settings:
            SettingsView()
        }
    }
}

#Preview {
    ContentView()
}
