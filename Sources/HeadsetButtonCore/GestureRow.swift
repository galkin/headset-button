import Foundation

/// The app that opens a URL's scheme, as `NSWorkspace.urlForApplication(toOpen:)` found it.
public struct URLHandler: Equatable, Sendable {
    public var appName: String
    /// The app bundle's path, for its icon.
    public var appPath: String

    public init(appName: String, appPath: String) {
        self.appName = appName
        self.appPath = appPath
    }
}

/// Whether an Open URL row's text is a URL some app opens.
public enum URLValidation: Equatable, Sendable {
    /// No text yet: the row is Incomplete, not wrong.
    case empty
    /// Text that does not parse as a URL with a scheme.
    case notAURL
    /// A URL whose scheme no installed app opens.
    case noApp(scheme: String)
    /// A URL that `handler` opens.
    case opens(URLHandler)

    /// The text as a URL with a non-empty scheme, or nil.
    public static func parse(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme, !scheme.isEmpty else { return nil }
        return url
    }

    /// The decision, given the row's text, its parse result and the handler lookup for it.
    public static func decide(text: String, url: URL?, handler: URLHandler?) -> URLValidation {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .empty }
        guard let url, let scheme = url.scheme, !scheme.isEmpty else { return .notAURL }
        guard let handler else { return .noApp(scheme: scheme) }
        return .opens(handler)
    }

    /// Parses `text` and looks up its handler with `lookup` (only when it parses).
    public static func validate(_ text: String, lookup: (URL) -> URLHandler?) -> URLValidation {
        let url = parse(text)
        return decide(text: text, url: url, handler: url.flatMap(lookup))
    }

    public var isValid: Bool {
        if case .opens = self { return true }
        return false
    }

    /// The caption under the URL field, or nil when there is nothing to say.
    public var caption: String? {
        switch self {
        case .empty: nil
        case .notAURL: "Not a URL: add a scheme, like superwhisper://"
        case .noApp(let scheme): "No app opens \(scheme)://"
        case .opens(let handler): "Opens in \(handler.appName)"
        }
    }
}

/// The State column of a Gestures table row.
public enum RowState: Equatable, Sendable {
    /// Action None: the row shows "—".
    case none
    case active
    case incomplete
    case invalidURL
    case needsAccessibility

    /// The State column's text; nil for a None row, which shows "—".
    public var title: String? {
        switch self {
        case .none: nil
        case .active: "Active"
        case .incomplete: "Incomplete"
        case .invalidURL: "Invalid URL"
        case .needsAccessibility: "Needs Accessibility"
        }
    }

    /// The row's Binding is in effect. A Press shortcut row waiting for Accessibility is a
    /// Binding all the same (it holds the slot; the status says Accessibility needed).
    public var applies: Bool {
        self == .active || self == .needsAccessibility
    }

    /// `urlValidation` is consulted only for an Open URL row.
    public static func derive(
        draft: BindingDraft,
        urlValidation: URLValidation,
        isAccessibilityTrusted: Bool
    ) -> RowState {
        switch draft.kind {
        case .none:
            return .none
        case .openURL:
            switch urlValidation {
            case .empty: return .incomplete
            case .notAURL, .noApp: return .invalidURL
            case .opens: return .active
            }
        case .pressShortcut:
            guard draft.shortcut != nil else { return .incomplete }
            return isAccessibilityTrusted ? .active : .needsAccessibility
        }
    }
}

/// One evaluated row of the Gestures table.
public struct GestureRow: Equatable, Sendable {
    public var gesture: Gesture
    public var draft: BindingDraft
    /// `.empty` unless the row is Open URL.
    public var urlValidation: URLValidation
    public var state: RowState

    /// The Binding in effect for this row, or nil.
    public var binding: Binding? {
        guard state.applies, let action = draft.action else { return nil }
        return Binding(gesture: gesture, action: action)
    }

    /// The Action the Run button fires: anything that parses, even an Invalid URL, so Run
    /// can show what happens. Nil for None and Incomplete rows (Run is disabled).
    public var runnableAction: Action? {
        state == .none || state == .incomplete ? nil : draft.action
    }
}

extension BindingSet {
    /// The Gestures table, in Gesture order. `lookup` finds the app for an Open URL row's URL.
    public func rows(isAccessibilityTrusted: Bool, lookup: (URL) -> URLHandler?) -> [GestureRow] {
        Gesture.allCases.map { gesture in
            let draft = self[gesture]
            let validation = draft.kind == .openURL ? URLValidation.validate(draft.urlText, lookup: lookup) : .empty
            return GestureRow(
                gesture: gesture,
                draft: draft,
                urlValidation: validation,
                state: RowState.derive(draft: draft, urlValidation: validation, isAccessibilityTrusted: isAccessibilityTrusted)
            )
        }
    }
}
