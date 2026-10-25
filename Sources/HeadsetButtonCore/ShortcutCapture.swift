import CoreGraphics

/// What the shortcut recorder does with one key-down it sees while recording.
public enum CaptureDecision: Equatable, Sendable {
    /// Esc alone: stop recording, keep the old shortcut.
    case cancel
    /// Delete or Forward Delete alone: stop recording, remove the shortcut.
    case clear
    /// Tab or Shift-Tab alone: stop recording and move keyboard focus to the next
    /// (or, with `backward`, the previous) control, as in any macOS form.
    case moveFocus(backward: Bool)
    /// A usable shortcut: store it and swallow the key so its owner doesn't fire.
    case capture(KeyCombo)
    /// Not a shortcut (a plain or Shift-only key): keep recording and swallow the key, so it
    /// never types into another field.
    case keepRecording
}

public extension KeyCombo {
    // Virtual key codes (HIToolbox/Events.h, kVK_*).
    static let escapeKeyCode = 53
    static let deleteKeyCode = 51
    static let forwardDeleteKeyCode = 117
    static let tabKeyCode = 48

    /// The KeyCombo for a key-down's key code and `CGEventFlags`, ignoring Caps Lock,
    /// Fn and the device-specific bits.
    init(keyCode: Int, flags: CGEventFlags) {
        var modifiers = 0
        if flags.contains(.maskCommand) { modifiers |= Self.cmdKey }
        if flags.contains(.maskShift) { modifiers |= Self.shiftKey }
        if flags.contains(.maskAlternate) { modifiers |= Self.optionKey }
        if flags.contains(.maskControl) { modifiers |= Self.controlKey }
        self.init(carbonKeyCode: keyCode, carbonModifiers: modifiers)
    }

    /// Has ⌃, ⌥ or ⌘ (Shift alone only changes the character).
    var hasCommandLikeModifier: Bool {
        carbonModifiers & (Self.cmdKey | Self.optionKey | Self.controlKey) != 0
    }

    /// F1–F20 work as shortcuts without modifiers.
    var isFunctionKey: Bool { Self.functionKeyNames[carbonKeyCode] != nil }

    /// Modifier symbols in Apple's order: ⌃⌥⇧⌘.
    var modifierSymbols: String {
        var symbols = ""
        if carbonModifiers & Self.controlKey != 0 { symbols += "⌃" }
        if carbonModifiers & Self.optionKey != 0 { symbols += "⌥" }
        if carbonModifiers & Self.shiftKey != 0 { symbols += "⇧" }
        if carbonModifiers & Self.cmdKey != 0 { symbols += "⌘" }
        return symbols
    }

    /// Name of a key that types no character (Space, Return, arrows, F-keys), or nil
    /// for a character key, whose name depends on the keyboard layout.
    var specialKeyName: String? {
        Self.functionKeyNames[carbonKeyCode] ?? Self.specialKeyNames[carbonKeyCode]
    }

    /// E.g. "⌃⌥⌘Space". `characterKeyName` is the layout's character for the key
    /// (the app looks it up); unknown keys show as "Key 42".
    func displayString(characterKeyName: String?) -> String {
        let name = specialKeyName
            ?? characterKeyName.flatMap { $0.isEmpty ? nil : $0.uppercased() }
            ?? "Key \(carbonKeyCode)"
        return modifierSymbols + name
    }

    private static let functionKeyNames: [Int: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    private static let specialKeyNames: [Int: String] = [
        49: "Space", 36: "↩", 76: "⌤", 48: "⇥", 53: "⎋", 51: "⌫", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟", 114: "Help",
    ]
}

public enum ShortcutCapture {
    /// Decides what one key-down means while the recorder is recording.
    public static func decide(keyCode: Int, flags: CGEventFlags) -> CaptureDecision {
        let combo = KeyCombo(keyCode: keyCode, flags: flags)
        if combo.carbonModifiers == 0 {
            if keyCode == KeyCombo.escapeKeyCode { return .cancel }
            if keyCode == KeyCombo.deleteKeyCode || keyCode == KeyCombo.forwardDeleteKeyCode { return .clear }
        }
        if keyCode == KeyCombo.tabKeyCode, !combo.hasCommandLikeModifier {
            return .moveFocus(backward: combo.carbonModifiers & KeyCombo.shiftKey != 0)
        }
        if combo.hasCommandLikeModifier || combo.isFunctionKey { return .capture(combo) }
        return .keepRecording
    }
}
