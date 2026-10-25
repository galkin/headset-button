/// What the shortcut recorder shows: one of three clearly different states.
public enum RecorderDisplay: Equatable, Sendable {
    /// No shortcut, not recording: "Record Shortcut".
    case empty
    /// Recording (the recorder has keyboard focus and its focus ring): "Type Shortcut…".
    case recording
    /// A shortcut is set, not recording: the combo and a clear button.
    case set(KeyCombo)

    public static let emptyTitle = "Record Shortcut"
    public static let recordingTitle = "Type Shortcut…"

    public init(combo: KeyCombo?, isRecording: Bool) {
        if isRecording {
            self = .recording
        } else if let combo {
            self = .set(combo)
        } else {
            self = .empty
        }
    }

    public var showsClearButton: Bool {
        if case .set = self { return true }
        return false
    }
}

/// What made the recorder the first responder; only a deliberate focus starts recording, so
/// AppKit picking the recorder as a window's first key view on its own doesn't.
public enum RecorderFocusCause: Equatable, Sendable {
    /// A mouse-down in this window; `insideRecorder` when it hit the recorder.
    case mouseDown(insideRecorder: Bool)
    /// A key-down in this window.
    case keyDown(keyCode: Int)
    /// Tab or Shift-Tab out of another recorder that was recording (its event tap swallowed the key).
    case tabFromRecorder
    /// Anything else: no current event, an event of another window, a programmatic change.
    case other

    public var startsRecording: Bool {
        switch self {
        case .mouseDown(let inside): inside
        case .keyDown(let keyCode): keyCode == KeyCombo.tabKeyCode
        case .tabFromRecorder: true
        case .other: false
        }
    }
}
