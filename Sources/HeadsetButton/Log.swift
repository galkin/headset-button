import os

/// `log stream --predicate 'subsystem == "in.galk.HeadsetButton"'` shows these (see AGENTS.md).
enum Log {
    static let subsystem = "in.galk.HeadsetButton"
    /// Every received remote command: Gesture, sourceID, accepted or dropped.
    static let gesture = Logger(subsystem: subsystem, category: "gesture")
    /// Holding, yielding and releasing the Now Playing slot.
    static let slot = Logger(subsystem: subsystem, category: "slot")
    /// Running Actions, Accessibility and launch at login.
    static let action = Logger(subsystem: subsystem, category: "action")
    /// The shortcut recorder's event tap: created or failed, captured combo, swallowed or not.
    static let recorder = Logger(subsystem: subsystem, category: "recorder")
    /// Headset mic busy: which devices are the Headset's input, busy or free, which app records.
    static let mic = Logger(subsystem: subsystem, category: "mic")
}
