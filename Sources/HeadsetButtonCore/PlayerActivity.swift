/// Tracks whether Spotify or Music is playing, from their distributed notifications.
/// A playing player owns the Now Playing slot and gets the Headset presses.
public struct PlayerActivity: Equatable, Sendable {
    public struct Player: Sendable {
        public let bundleID: String
        public let notificationName: String
        public let name: String
    }

    public static let players: [Player] = [
        Player(
            bundleID: "com.spotify.client", notificationName: "com.spotify.client.PlaybackStateChanged", name: "Spotify"
        ),
        Player(bundleID: "com.apple.Music", notificationName: "com.apple.Music.playerInfo", name: "Music"),
    ]

    /// The userInfo key both players use; its value is "Playing", "Paused" or "Stopped".
    public static let playerStateKey = "Player State"

    private var playing: Set<String> = []

    public init() {}

    public var isAnyPlaying: Bool { !playing.isEmpty }

    /// The name of a playing player (the first in `players` order), or nil.
    public var playingPlayerName: String? {
        Self.players.first { playing.contains($0.bundleID) }?.name
    }

    public static func bundleID(forNotification name: String) -> String? {
        players.first { $0.notificationName == name }?.bundleID
    }

    /// Records a player's state notification; a missing state counts as not playing.
    public mutating func record(notification name: String, playerState: String?) {
        guard let bundleID = Self.bundleID(forNotification: name) else { return }
        if playerState == "Playing" {
            playing.insert(bundleID)
        } else {
            playing.remove(bundleID)
        }
    }

    public mutating func playerQuit(bundleID: String) {
        playing.remove(bundleID)
    }
}
