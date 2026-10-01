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
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var migrationErrorMessage: String?
    @State private var isShortcutHelpPresented = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("Kotoba")
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            detailView(for: selection ?? .today)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 720, minHeight: 560)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    isShortcutHelpPresented = true
                } label: {
                    Label("快捷键帮助", systemImage: "questionmark.circle")
                }
                .help("查看快捷键帮助")
                .accessibilityLabel("快捷键帮助")
            }
        }
        .sheet(isPresented: $isShortcutHelpPresented) {
            KeyboardShortcutHelpView()
        }
        .task {
            await loadInitialWordBooks()
        }
        .alert(
            "数据加载失败",
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
            WordBookManagementView {
                selection = .wordbook
            }
        case .statistics:
            StatisticsView()
        case .kanaChart:
            KanaChartView()
        case .settings:
            SettingsView()
        }
    }

    private func loadInitialWordBooks() async {
        do {
            _ = try await BuiltInWordBookInitializationCoordinator.shared.loadIfNeeded(in: modelContext)
            try PerformanceTrace.measure("Legacy word migration") {
                try WordBookService().migrateLegacyWordsIfNeeded(in: modelContext)
            }
            migrationErrorMessage = nil
        } catch {
            #if DEBUG
            print("[Kotoba] Initial wordbook loading failed:", error.localizedDescription)
            #endif
            migrationErrorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ContentView()
}
