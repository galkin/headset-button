import CoreGraphics
import Foundation

/// A keyboard shortcut as Carbon key code and Carbon modifier mask (stored in Bindings).
public struct KeyCombo: Codable, Equatable, Hashable, Sendable {
    public var carbonKeyCode: Int
    public var carbonModifiers: Int

    public init(carbonKeyCode: Int, carbonModifiers: Int) {
        self.carbonKeyCode = carbonKeyCode
        self.carbonModifiers = carbonModifiers
    }

    // Carbon modifier bits (HIToolbox/Events.h).
    public static let cmdKey = 1 << 8
    public static let shiftKey = 1 << 9
    public static let optionKey = 1 << 11
    public static let controlKey = 1 << 12

    /// Virtual key code for a synthetic `CGEvent`; Carbon key codes are the same numbers.
    public var virtualKeyCode: CGKeyCode { CGKeyCode(truncatingIfNeeded: carbonKeyCode) }

    /// Modifier flags to put on the synthetic key events.
    public var eventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if carbonModifiers & Self.cmdKey != 0 { flags.insert(.maskCommand) }
        if carbonModifiers & Self.shiftKey != 0 { flags.insert(.maskShift) }
        if carbonModifiers & Self.optionKey != 0 { flags.insert(.maskAlternate) }
        if carbonModifiers & Self.controlKey != 0 { flags.insert(.maskControl) }
        return flags
    }
}

/// What the app does on the Mac in response to a Gesture.
public enum Action: Equatable, Sendable {
    case openURL(URL)
    case pressShortcut(KeyCombo)
}

/// The user's chosen pairing of one Gesture with one Action.
public struct Binding: Equatable, Sendable {
    public var gesture: Gesture
    public var action: Action

    public init(gesture: Gesture, action: Action) {
        self.gesture = gesture
        self.action = action
    }
}

/// The Action kinds offered by the Settings picker.
public enum ActionKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case none
    case openURL
    case pressShortcut

    public var id: Self { self }

    public var title: String {
        switch self {
        case .none: "None"
        case .openURL: "Open URL"
        case .pressShortcut: "Press shortcut"
        }
    }
}

/// What one Settings row holds for a Gesture. It keeps the URL text and the shortcut
/// even while another kind is picked, and becomes a Binding only once it is complete.
public struct BindingDraft: Codable, Equatable, Sendable {
    public var kind: ActionKind
    public var urlText: String
    public var shortcut: KeyCombo?

    public init(kind: ActionKind = .none, urlText: String = "", shortcut: KeyCombo? = nil) {
        self.kind = kind
        self.urlText = urlText
        self.shortcut = shortcut
    }

    /// The Action this draft runs, or nil when it is None or incomplete.
    public var action: Action? {
        switch kind {
        case .none:
            return nil
        case .openURL:
            return URLValidation.parse(urlText).map(Action.openURL)
        case .pressShortcut:
            return shortcut.map(Action.pressShortcut)
        }
    }
}

/// The drafts for all Gestures, and the Bindings they yield. Empty on first launch.
public struct BindingSet: Codable, Equatable, Sendable {
    public var drafts: [Gesture: BindingDraft]

    public init(drafts: [Gesture: BindingDraft] = [:]) {
        self.drafts = drafts
    }

    public subscript(gesture: Gesture) -> BindingDraft {
        get { drafts[gesture] ?? BindingDraft() }
        set { drafts[gesture] = newValue }
    }

    public func binding(for gesture: Gesture) -> Binding? {
        self[gesture].action.map { Binding(gesture: gesture, action: $0) }
    }

    /// Complete Bindings, in Gesture order.
    public var bindings: [Binding] {
        Gesture.allCases.compactMap(binding(for:))
    }

    /// Some row has "Press shortcut" picked (complete or not): Settings shows Permissions.
    public var hasPressShortcutKind: Bool {
        Gesture.allCases.contains { self[$0].kind == .pressShortcut }
    }

    /// Some complete Binding presses a shortcut: it needs Accessibility to work.
    public var hasPressShortcutBinding: Bool { bindings.containsPressShortcut }
}

extension [Binding] {
    public var containsPressShortcut: Bool {
        contains { if case .pressShortcut = $0.action { true } else { false } }
    }
}

/// Persists the BindingSet and the Enabled toggle in `UserDefaults`.
public struct BindingStore: @unchecked Sendable {
    public static let bindingsKey = "bindings.v1"
    public static let enabledKey = "enabled"
    public static let accessibilityRequestedKey = "accessibilityRequested"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public static func decode(_ data: Data?) -> BindingSet {
        guard let data, let set = try? JSONDecoder().decode(BindingSet.self, from: data) else {
            return BindingSet()
        }
        return set
    }

    public static func encode(_ set: BindingSet) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Encoding plain Codable values into JSON cannot fail.
        return (try? encoder.encode(set)) ?? Data()
    }

    public func loadBindings() -> BindingSet {
        Self.decode(defaults.data(forKey: Self.bindingsKey))
    }

    public func saveBindings(_ set: BindingSet) {
        defaults.set(Self.encode(set), forKey: Self.bindingsKey)
    }

    /// Enabled defaults to on.
    public var isEnabled: Bool {
        get { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    /// Whether the one-time Accessibility prompt has been shown.
    public var accessibilityRequested: Bool {
        get { defaults.bool(forKey: Self.accessibilityRequestedKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.accessibilityRequestedKey) }
    }
}
