import AppKit

final class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        guard modifiers == .command,
              let editor = firstResponder as? NSTextView,
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        // Nonactivating panels can retain the other app's menu bar while typing.
        // Route editing keys directly to this panel's focused text editor.
        switch key {
        case "v": editor.paste(nil)
        case "c": editor.copy(nil)
        case "x": editor.cut(nil)
        case "a": editor.selectAll(nil)
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }
}
