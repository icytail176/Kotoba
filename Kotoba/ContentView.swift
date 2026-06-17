//
//  ContentView.swift
//  Kotoba
//
//  Created by Fumi on 2026/6/16.
//

import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selection: AppSection? = .today
    @State private var migrationErrorMessage: String?

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("Kotoba")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            detailView(for: selection ?? .today)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 720, minHeight: 560)
        .task {
            migrateLegacyWordsIfNeeded()
        }
        .alert(
            "数据迁移失败",
            isPresented: Binding(
                get: { migrationErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        migrationErrorMessage = nil
                    }
                }
            )
        ) {
            Button("好") {
                migrationErrorMessage = nil
            }
        } message: {
            Text(migrationErrorMessage ?? "")
        }
    }

    @ViewBuilder
    private func detailView(for section: AppSection) -> some View {
        switch section {
        case .today:
            TodayStudyView {
                selection = .wordBooks
            }
        case .wordbook:
            WordbookView()
        case .wordBooks:
            WordBookManagementView()
        case .statistics:
            StatisticsView()
        case .settings:
            SettingsView()
        }
    }

    private func migrateLegacyWordsIfNeeded() {
        do {
            try WordBookService().migrateLegacyWordsIfNeeded(in: modelContext)
        } catch {
            migrationErrorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ContentView()
}
