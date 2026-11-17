import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class ShelfShortcut: ObservableObject {
    @Published private(set) var label = ""
    @Published private(set) var recording = false
    @Published private(set) var message = ""
    var onToggle: (() -> Void)?

    private var registration: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var monitor: Any?
    private var current: Binding?
    private let defaults = UserDefaults.standard
    private let signature: OSType = 0x4A53484C

    private struct Binding: Equatable {
        let code: UInt32
        let modifiers: UInt32
        let label: String
    }

    func start() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<ShelfShortcut>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                if !shortcut.recording { shortcut.onToggle?() }
            }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)

        guard result == noErr else {
            message = "Couldn’t start the keyboard shortcut."
            return
        }
        let saved = defaults.dictionary(forKey: "shelfShortcut")
        let binding = Binding(code: saved?["code"] as? UInt32 ?? UInt32(kVK_ANSI_J),
                              modifiers: saved?["modifiers"] as? UInt32 ?? UInt32(controlKey | optionKey | cmdKey),
                              label: saved?["label"] as? String ?? "⌃⌥⌘J")
        set(binding)
    }

    func record(in panel: NSPanel) {
        guard handler != nil else { return }
        if recording { cancel(); return }
        recording = true
        message = ""
        panel.makeKeyAndOrderFront(nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, let panel, event.window === panel else { return event }
            MainActor.assumeIsolated { self.capture(event) }
            return nil
        }
    }

    func cancel() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }

    func stop() {
        cancel()
        if let registration { UnregisterEventHotKey(registration) }
        if let handler { RemoveEventHandler(handler) }
        registration = nil
        handler = nil
    }

    private func capture(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) { cancel(); return }
        let flags = event.modifierFlags
        guard flags.contains(.command) || flags.contains(.control) else {
            message = "Include Command or Control in the shortcut."
            return
        }

        let keys: [(NSEvent.ModifierFlags, Int, String)] = [
            (.control, controlKey, "⌃"), (.option, optionKey, "⌥"),
            (.shift, shiftKey, "⇧"), (.command, cmdKey, "⌘")
        ]
        let selected = keys.filter { flags.contains($0.0) }
        let modifiers = selected.reduce(UInt32(0)) { $0 | UInt32($1.1) }
        let key: String
        switch Int(event.keyCode) {
        case kVK_Space: key = "Space"
        case kVK_Return: key = "↩"
        case kVK_Tab: key = "⇥"
        case kVK_Delete: key = "⌫"
        case kVK_LeftArrow: key = "←"
        case kVK_RightArrow: key = "→"
        case kVK_UpArrow: key = "↑"
        case kVK_DownArrow: key = "↓"
        default:
            guard let characters = event.charactersIgnoringModifiers, !characters.isEmpty,
                  characters.unicodeScalars.allSatisfy({ !$0.properties.isWhitespace && $0.value < 0xF700 }) else {
                message = "Choose a letter, number, or arrow key."
                return
            }
            key = characters.uppercased()
        }
        if set(Binding(code: UInt32(event.keyCode), modifiers: modifiers,
                       label: selected.map(\.2).joined() + key)) { cancel() }
    }

    @discardableResult
    private func set(_ binding: Binding) -> Bool {
        if binding == current { return true }
        var next: EventHotKeyRef?
        let id = EventHotKeyID(signature: signature, id: current == nil ? 1 : nextID)
        guard RegisterEventHotKey(binding.code, binding.modifiers, id,
                                  GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &next) == noErr,
              let next else {
            message = "That shortcut is unavailable. Try another combination."
            return false
        }
        nextID = id.id == 1 ? 2 : 1
        if let registration { UnregisterEventHotKey(registration) }
        registration = next
        current = binding
        label = binding.label
        message = ""
        defaults.set(["code": binding.code, "modifiers": binding.modifiers, "label": binding.label],
                     forKey: "shelfShortcut")
        return true
    }

    private var nextID: UInt32 = 2
}
