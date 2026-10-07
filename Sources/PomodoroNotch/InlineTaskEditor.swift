import AppKit
import SwiftUI
import PomodoroCore

private final class AutofocusingTextField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(self)
            self.selectText(nil)
        }
    }
}

struct InlineTaskEditor: NSViewRepresentable {
    var initialText: String
    var onTextChanged: (String) -> Void
    var onCommit: (String) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = AutofocusingTextField()
        field.stringValue = initialText
        field.isEditable = true
        field.isSelectable = true
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 12)
        field.textColor = .white
        field.placeholderAttributedString = NSAttributedString(
            string: "Task (optional)", attributes: [.foregroundColor: NSColor.white.withAlphaComponent(0.6)])
        field.setAccessibilityLabel("Focus task, optional")
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InlineTaskEditor
        private var finished = false
        private var value: String
        init(parent: InlineTaskEditor) { self.parent = parent; value = parent.initialText }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            value = String(field.stringValue.unicodeScalars.filter {
                !CharacterSet.controlCharacters.contains($0)
            }.prefix(160))
            parent.onTextChanged(value)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) { end(commit: true); return true }
            if selector == #selector(NSResponder.cancelOperation(_:)) { end(commit: false); return true }
            return false
        }

        private func end(commit: Bool) {
            guard !finished else { return }
            finished = true
            if commit { parent.onCommit(value) } else { parent.onCancel() }
        }
    }
}

struct InlineDurationEditor: NSViewRepresentable {
    var initialSeconds: Int
    var onTextChanged: (String) -> Void
    var onCommit: (Int) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = AutofocusingTextField()
        field.stringValue = FocusDuration.clock(initialSeconds)
        field.isEditable = true
        field.isSelectable = true
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = .center
        field.font = .monospacedDigitSystemFont(ofSize: 24, weight: .regular)
        field.textColor = .white
        field.setAccessibilityLabel("Focus duration, minutes and seconds")
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InlineDurationEditor
        init(parent: InlineDurationEditor) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.onTextChanged(field.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                if let seconds = FocusDuration.parse(control.stringValue) {
                    parent.onCommit(seconds)
                } else { NSSound.beep() }
                return true
            }
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }
    }
}
