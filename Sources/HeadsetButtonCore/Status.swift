/// Why the app is not listening while it is Paused (the Now Playing slot is released).
public enum PauseReason: Equatable, Sendable {
    case disabled
    case noBindings
}

/// The app's overall status: the menu's status line, and in Settings the same plus its reason.
public enum ListenerStatus: Equatable, Sendable {
    case listening
    case paused(PauseReason)
    /// Headset mic busy; `app` is the recording app's name when CoreAudio names it.
    case headsetMicBusy(app: String?)
    case accessibilityNeeded
    /// No Bluetooth audio device with output is connected, so there is no Headset to listen to.
    case noHeadset
    /// A media player owns the Now Playing slot; `player` is its name.
    case playerHasHeadset(player: String?)

    /// The menu's status line.
    public var title: String {
        switch self {
        case .listening: "Listening"
        case .paused: "Paused"
        case .headsetMicBusy: "Headset mic in use"
        case .accessibilityNeeded: "Accessibility needed"
        case .noHeadset: "No headset connected"
        case .playerHasHeadset: "Player has the headset"
        }
    }

    /// The Settings window's status line: the status plus its reason.
    public var detail: String {
        switch self {
        case .listening: "Listening — press your AirPods"
        case .paused(.disabled): "Not listening: disabled in menu"
        case .paused(.noBindings): "Not listening: no active Bindings"
        case .headsetMicBusy(let app): "Not listening: \(app ?? "An app") is recording from the headset mic"
        case .accessibilityNeeded: "Not listening: Accessibility needed"
        case .noHeadset: "Not listening: no headset connected"
        case .playerHasHeadset(let player): "Not listening: \(player ?? "A media player") is playing"
        }
    }

    /// The menu bar icon is full only while Listening; every other status dims it.
    public var isActive: Bool { self == .listening }
}

/// Everything the status and the Now Playing slot depend on.
public struct ListenerState: Equatable, Sendable {
    public var isEnabled: Bool
    /// The Bindings in effect (rows whose State applies).
    public var bindings: [Binding]
    public var isAccessibilityTrusted: Bool
    /// The name of the media player that is playing, or nil.
    public var playingPlayer: String?
    /// Set while the Headset mic is busy: the recording app's name, or nil when unknown.
    public var headsetMicBusy: HeadsetMicBusy?
    /// The connected Headsets (Bluetooth audio devices with output, default output or not);
    /// any one of them is enough.
    public var headsets: [Headset]

    public init(
        isEnabled: Bool,
        bindings: [Binding],
        isAccessibilityTrusted: Bool,
        playingPlayer: String? = nil,
        headsetMicBusy: HeadsetMicBusy? = nil,
        headsets: [Headset]
    ) {
        self.isEnabled = isEnabled
        self.bindings = bindings
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.playingPlayer = playingPlayer
        self.headsetMicBusy = headsetMicBusy
        self.headsets = headsets
    }

    /// The slot is held only while a Binding exists, Enabled is on and a Headset is connected.
    /// Headset mic busy does not release it: presses come back as soon as the mic is free.
    public var holdsSlot: Bool { isEnabled && !bindings.isEmpty && !headsets.isEmpty }

    /// Why the slot is held or released, for the `slot` log.
    public var slotReason: String {
        if !isEnabled { return "released: disabled in menu" }
        if bindings.isEmpty { return "released: no active Bindings" }
        if headsets.isEmpty { return "released: no headset connected" }
        let count = bindings.count == 1 ? "1 Binding" : "\(bindings.count) Bindings"
        let names = headsets.map(\.name).joined(separator: ", ")
        return "held: \(count), Enabled on, \(headsets.count == 1 ? "headset" : "headsets") \(names)"
    }

    /// While holding, step back (pause the silent loop) when a media player is playing.
    public var yieldsToPlayer: Bool { holdsSlot && playingPlayer != nil }

    /// Precedence, first match wins: disabled in menu, no active Bindings, no headset
    /// connected, Headset mic busy, Accessibility needed, player has the headset, Listening.
    public var status: ListenerStatus {
        if !isEnabled { return .paused(.disabled) }
        if bindings.isEmpty { return .paused(.noBindings) }
        if headsets.isEmpty { return .noHeadset }
        if let busy = headsetMicBusy { return .headsetMicBusy(app: busy.appName) }
        if bindings.containsPressShortcut && !isAccessibilityTrusted { return .accessibilityNeeded }
        if let player = playingPlayer { return .playerHasHeadset(player: player) }
        return .listening
    }
}
