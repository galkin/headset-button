/// The `MPRemoteCommandCenter` commands the app listens to (ADR 0001).
/// A single press on AirPods Max arrives as `play` or `pause` (AVRCP Play/Pause), not `togglePlayPause`.
public enum RemoteCommand: String, CaseIterable, Sendable {
    case play
    case pause
    case togglePlayPause
    case nextTrack
    case previousTrack
}

/// One kind of Headset press the app can tell apart.
public enum Gesture: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable, Identifiable {
    case single
    case double
    case triple

    public var id: Self { self }

    /// The Gesture a Headset press arrives as, given the remote command it produced.
    public init(command: RemoteCommand) {
        switch command {
        case .play, .pause, .togglePlayPause: self = .single
        case .nextTrack: self = .double
        case .previousTrack: self = .triple
        }
    }

    public var title: String {
        switch self {
        case .single: "Single press"
        case .double: "Double press"
        case .triple: "Triple press"
        }
    }

    /// The short name in "Last press: Single, 3 s ago".
    public var shortTitle: String {
        switch self {
        case .single: "Single"
        case .double: "Double"
        case .triple: "Triple"
        }
    }
}
