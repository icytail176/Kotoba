//
//  IMEAwareTextField.swift
//  Kotoba
//
//  Created by Codex on 2026/6/18.
//

import AppKit
import SwiftUI

struct IMEAwareTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let placeholder: String
    let isEnabled: Bool
    let onSubmit: (_ isMarkedTextActive: Bool) -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.placeholderString = placeholder
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .default
        textField.usesSingleLineMode = true
        textField.lineBreakMode = .byTruncatingTail
        textField.font = .systemFont(ofSize: 20)
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self

        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        nsView.placeholderString = placeholder
        nsView.isEnabled = isEnabled
        nsView.isEditable = isEnabled
        nsView.textColor = isEnabled ? .labelColor : .secondaryLabelColor

        DispatchQueue.main.async {
            guard let window = nsView.window else {
                return
            }

            if isFocused && isEnabled {
                if !Self.isFirstResponder(nsView) {
                    window.makeFirstResponder(nsView)
                }
            } else if Self.isFirstResponder(nsView) {
                window.makeFirstResponder(nil)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private static func isFirstResponder(_ textField: NSTextField) -> Bool {
        guard let firstResponder = textField.window?.firstResponder else {
            return false
        }

        return firstResponder === textField || firstResponder === textField.currentEditor()
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: IMEAwareTextField

        init(parent: IMEAwareTextField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.isFocused = true
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }

            parent.text = textField.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:))
                    || commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) else {
                return false
            }

            if textView.hasMarkedText() {
                parent.onSubmit(true)
                return false
            }

            parent.onSubmit(false)
            return true
        }
    }
}
