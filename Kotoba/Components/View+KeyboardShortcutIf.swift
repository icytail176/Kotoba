//
//  View+KeyboardShortcutIf.swift
//  Kotoba
//
//  Created by Codex on 2026/6/17.
//

import SwiftUI

extension View {
    @ViewBuilder
    func keyboardShortcutIf(
        _ enabled: Bool,
        _ key: KeyEquivalent,
        modifiers: EventModifiers = .command
    ) -> some View {
        if enabled {
            keyboardShortcut(key, modifiers: modifiers)
        } else {
            self
        }
    }
}
