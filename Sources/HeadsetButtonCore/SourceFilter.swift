/// Decides whether a remote command came from the Headset (ADR 0001): keep commands
/// whose private `MPRemoteCommandEvent.sourceID` names `com.apple.bluetoothd`.
public enum SourceDecision: Equatable, Sendable {
    /// The sender is bluetoothd: a Gesture.
    case accepted
    /// `sourceID` could not be read, so the filter is bypassed and the command accepted.
    case acceptedUnfiltered
    /// Another sender (keyboard media keys via `com.apple.rcd`, Control Center, scripts).
    case dropped

    public var accepts: Bool { self != .dropped }

    public var logDescription: String {
        switch self {
        case .accepted: "accepted"
        case .acceptedUnfiltered: "accepted (filter bypassed: sourceID unreadable)"
        case .dropped: "dropped (not the headset)"
        }
    }
}

public enum SourceFilter {
    public static let headsetSender = "com.apple.bluetoothd"

    public static func decide(sourceID: String?) -> SourceDecision {
        guard let sourceID, !sourceID.isEmpty else { return .acceptedUnfiltered }
        return sourceID.contains(headsetSender) ? .accepted : .dropped
    }
}
