import Foundation
import Testing

@testable import HeadsetButtonCore

@Suite struct PlayerActivityTests {
    @Test func tracksPlayingPlayers() {
        var activity = PlayerActivity()
        #expect(!activity.isAnyPlaying)
        activity.record(notification: "com.spotify.client.PlaybackStateChanged", playerState: "Playing")
        activity.record(notification: "com.apple.Music.playerInfo", playerState: "Playing")
        activity.record(notification: "com.spotify.client.PlaybackStateChanged", playerState: "Paused")
        #expect(activity.isAnyPlaying)
        activity.record(notification: "com.apple.Music.playerInfo", playerState: "Stopped")
        #expect(!activity.isAnyPlaying)
    }

    @Test func quitAndUnknownNotifications() {
        var activity = PlayerActivity()
        activity.record(notification: "com.apple.Music.playerInfo", playerState: "Playing")
        activity.record(notification: "com.example.other", playerState: "Stopped")
        #expect(activity.isAnyPlaying)
        activity.playerQuit(bundleID: "com.apple.Music")
        #expect(!activity.isAnyPlaying)
        activity.record(notification: "com.example.other", playerState: "Playing")
        #expect(!activity.isAnyPlaying)
    }
}

@Suite struct SilentAudioTests {
    @Test func wavHeaderAndSilence() {
        let data = SilentAudio.wavData(seconds: 0.5, sampleRate: 8_000)
        #expect(data.count == 44 + 8_000)
        #expect(String(decoding: data.prefix(4), as: UTF8.self) == "RIFF")
        #expect(String(decoding: data[8..<12], as: UTF8.self) == "WAVE")
        #expect(String(decoding: data[36..<40], as: UTF8.self) == "data")
        #expect(data.dropFirst(44).allSatisfy { $0 == 0 })
    }
}
