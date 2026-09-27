//
//  KotobaApp.swift
//  Kotoba
//
//  Created by Fumi on 2026/6/16.
//

import AppKit
import SwiftData
import SwiftUI

enum KotobaRuntime {
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }
}

@main
struct KotobaApp: App {
    init() {
        guard !KotobaRuntime.isRunningTests else { return }
        Task.detached(priority: .utility) {
            LegacyCacheCleanupService.runIfNeeded()
        }
    }

    var body: some Scene {
        WindowGroup {
            KotobaDatabaseRootView()
        }
        .defaultSize(KotobaWindowSizing.defaultSize(for: NSScreen.main?.visibleFrame.size))
    }
}

enum KotobaWindowSizing {
    static let fallbackSize = CGSize(width: 1_100, height: 760)

    static func defaultSize(for visibleScreenSize: CGSize?) -> CGSize {
        guard let visibleScreenSize,
              visibleScreenSize.width > 0,
              visibleScreenSize.height > 0 else {
            return fallbackSize
        }

        let horizontalMargin = min(80, max(24, visibleScreenSize.width * 0.05))
        let verticalMargin = min(60, max(24, visibleScreenSize.height * 0.05))
        let maximumAvailableWidth = max(720, visibleScreenSize.width - horizontalMargin * 2)
        let maximumAvailableHeight = max(560, visibleScreenSize.height - verticalMargin * 2)
        let preferredWidth = min(1_180, max(900, visibleScreenSize.width * 0.78))
        let preferredHeight = min(840, max(700, visibleScreenSize.height * 0.82))

        return CGSize(
            width: min(preferredWidth, maximumAvailableWidth),
            height: min(preferredHeight, maximumAvailableHeight)
        )
    }
}

private struct KotobaDatabaseRootView: View {
    private enum LoadState {
        case loading
        case ready(ModelContainer)
        case failed(String)
    }

    @State private var loadState: LoadState = .loading

    var body: some View {
        Group {
            switch loadState {
            case .loading:
                ProgressView("正在打开学习数据库…")
                    .frame(minWidth: 520, minHeight: 320)
            case .ready(let container):
                ContentView()
                    .modelContainer(container)
            case .failed(let message):
                databaseErrorView(message: message)
            }
        }
        .task {
            guard !KotobaRuntime.isRunningTests else { return }
            guard case .loading = loadState else { return }
            await Task.yield()
            openDatabase()
        }
    }

    private func databaseErrorView(message: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.orange)

            Text("无法升级 Kotoba 学习数据库")
                .font(.title2.weight(.semibold))

            Text("原数据尚未删除。\n\(message)")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 520)

            HStack {
                Button("重试") {
                    loadState = .loading
                    openDatabase()
                }
                .keyboardShortcut(.defaultAction)

                Button("打开备份位置") {
                    NSWorkspace.shared.open(KotobaStore.backupRootURL)
                }

                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(36)
        .frame(minWidth: 620, minHeight: 380)
    }

    private func openDatabase() {
        do {
            loadState = .ready(
                try PerformanceTrace.measure("Default model container creation") {
                    try KotobaStore.makeDefaultContainer()
                }
            )
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}
