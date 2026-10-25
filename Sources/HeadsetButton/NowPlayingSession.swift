import AppKit
import AVFoundation
import Foundation
import HeadsetButtonCore
import MediaPlayer
import ObjectiveC

/// Holds the system's Now Playing slot with a looping silent audio file and turns the
/// three remote commands into Gestures (ADR 0001). The silent loop is deliberate.
@MainActor
final class NowPlayingSession {
    private enum Mode: Equatable { case released, holding, yielding }

    private let onGesture: @MainActor @Sendable (Gesture) -> Void
    private var mode: Mode = .released
    private var player: AVAudioPlayer?
    private var targets: [(command: MPRemoteCommand, token: Any)] = []

    init(onGesture: @escaping @MainActor @Sendable (Gesture) -> Void) {
        self.onGesture = onGesture
    }

    /// Brings the slot in line with `ListenerState.holdsSlot` / `yieldsToPlayer`.
    func update(hold: Bool, yieldToPlayer: Bool) {
        let wanted: Mode = !hold ? .released : (yieldToPlayer ? .yielding : .holding)
        guard wanted != mode else { return }
        let previous = mode
        mode = wanted

        switch wanted {
        case .released:
            release()
        case .holding:
            if previous == .released { addTargets() }
            assertSlot()
        case .yielding:
            if previous == .released { addTargets() }
            player?.pause()
            MPNowPlayingInfoCenter.default().playbackState = .paused
            Log.slot.notice("Yielding the Now Playing slot: a media player is playing")
        }
    }

    /// Called on a timer: re-asserts the slot in case another app took it.
    func heartbeat() {
        guard mode == .holding else { return }
        assertSlot(quietly: true)
    }

    // MARK: - Slot

    private func assertSlot(quietly: Bool = false) {
        let player = self.player ?? makePlayer()
        if let player, !player.isPlaying { player.play() }
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = Self.nowPlayingInfo
        center.playbackState = .playing
        if !quietly { Log.slot.notice("Holding the Now Playing slot") }
    }

    /// What the Now Playing widget shows while we hold the slot. The widget cannot be hidden
    /// (tried 2026-10-25, see ADR 0001), so it at least says what the app is doing.
    private static let nowPlayingInfo: [String: Any] = {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: "Headset Button",
            MPMediaItemPropertyArtist: "Listening for headset presses",
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
        // The bundle's AppIcon.icns, or the generic app icon when it is missing.
        if let icon = NSApplication.shared.applicationIconImage {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: icon.size) { _ in icon }
        }
        return info
    }()

    private func release() {
        for target in targets {
            target.command.removeTarget(target.token)
            target.command.isEnabled = false
        }
        targets = []
        player?.stop()
        player = nil
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = nil
        center.playbackState = .stopped
        Log.slot.notice("Released the Now Playing slot")
    }

    private func makePlayer() -> AVAudioPlayer? {
        do {
            let player = try AVAudioPlayer(data: SilentAudio.wavData(), fileTypeHint: AVFileType.wav.rawValue)
            player.numberOfLoops = -1
            player.prepareToPlay()
            self.player = player
            return player
        } catch {
            Log.slot.error("Could not create the silent audio player: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Commands

    private func addTargets() {
        let center = MPRemoteCommandCenter.shared()
        for command in RemoteCommand.allCases {
            let mpCommand = Self.mpCommand(command, in: center)
            mpCommand.isEnabled = true
            let token = mpCommand.addTarget(handler: Self.makeHandler(command: command, onGesture: onGesture))
            targets.append((mpCommand, token))
        }
    }

    private static func mpCommand(_ command: RemoteCommand, in center: MPRemoteCommandCenter) -> MPRemoteCommand {
        switch command {
        case .play: center.playCommand
        case .pause: center.pauseCommand
        case .togglePlayPause: center.togglePlayPauseCommand
        case .nextTrack: center.nextTrackCommand
        case .previousTrack: center.previousTrackCommand
        }
    }

    /// Built outside the main actor: MediaPlayer may call it on any thread.
    nonisolated private static func makeHandler(
        command: RemoteCommand,
        onGesture: @escaping @MainActor @Sendable (Gesture) -> Void
    ) -> (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        { event in
            let gesture = Gesture(command: command)
            let sourceID = PrivateEventFields.string(of: event, key: "sourceID")
            let decision = SourceFilter.decide(sourceID: sourceID)
            Log.gesture.notice("""
                command=\(command.rawValue, privacy: .public) gesture=\(gesture.rawValue, privacy: .public) \
                sourceID=\(sourceID ?? "unreadable", privacy: .public) \
                decision=\(decision.logDescription, privacy: .public)
                """)
            guard decision.accepts else { return .commandFailed }
            Task { @MainActor in onGesture(gesture) }
            return .success
        }
    }
}

/// Reads private `MPRemoteCommandEvent` fields via KVC without risking an
/// `NSUndefinedKeyException`: the key is read only if a getter or ivar exists.
enum PrivateEventFields {
    nonisolated static func string(of object: NSObject, key: String) -> String? {
        let hasGetter = object.responds(to: NSSelectorFromString(key))
        let hasIvar = class_getInstanceVariable(type(of: object), "_\(key)") != nil
        guard hasGetter || hasIvar else { return nil }
        guard let value = object.value(forKey: key), !(value is NSNull) else { return nil }
        if let string = value as? String { return string }
        return String(describing: value).replacingOccurrences(of: "\n", with: " ")
    }
}
