//
//  KotobaApp.swift
//  Kotoba
//
//  Created by Fumi on 2026/6/16.
//

import SwiftUI
import SwiftData

@main
struct KotobaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: KotobaSchema.models)
    }
}
