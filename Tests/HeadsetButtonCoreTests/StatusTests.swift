import Foundation
import Testing
@testable import HeadsetButtonCore

@Suite struct StatusTests {
    static let urlBinding = Binding(gesture: .single, action: .openURL(URL(string: "superwhisper://record")!))
    static let shortcutBinding = Binding(
        gesture: .double,
        action: .pressShortcut(KeyCombo(carbonKeyCode: 49, carbonModifiers: KeyCombo.cmdKey))
    )
    static let zoomBusy = HeadsetMicBusy(appName: "Zoom", headsetName: "AirPods Max")
    static let airPods = Headset(id: 42, name: "AirPods Max", transport: .bluetooth)

    func state(
        enabled: Bool = true,
        bindings: [Binding] = [urlBinding],
        trusted: Bool = false,
        player: String? = nil,
        busy: HeadsetMicBusy? = nil,
        headsets: [Headset] = [airPods]
    ) -> ListenerState {
        ListenerState(
            isEnabled: enabled, bindings: bindings, isAccessibilityTrusted: trusted,
            playingPlayer: player, headsetMicBusy: busy, headsets: headsets
        )
    }

    @Test func noHeadsetReleasesTheSlot() {
        let s = state(headsets: [])
        #expect(s.status == .noHeadset)
        #expect(!s.holdsSlot)
        #expect(!s.yieldsToPlayer)
        #expect(!s.status.isActive)
        #expect(s.slotReason == "released: no headset connected")
    }

    @Test func slotReasons() {
        #expect(state().slotReason == "held: 1 Binding, Enabled on, headset AirPods Max")
        #expect(state(bindings: [Self.urlBinding, Self.shortcutBinding]).slotReason.hasPrefix("held: 2 Bindings"))
        #expect(state(enabled: false).slotReason == "released: disabled in menu")
        #expect(state(bindings: [], headsets: []).slotReason == "released: no active Bindings")
    }

    @Test func slotReasonNamesEveryConnectedHeadset() {
        let beats = Headset(id: 7, name: "Beats", transport: .bluetoothLE)
        let s = state(headsets: [Self.airPods, beats])
        #expect(s.holdsSlot)
        #expect(s.status == .listening)
        #expect(s.slotReason == "held: 1 Binding, Enabled on, headsets AirPods Max, Beats")
    }

    @Test func listeningWithABindingAndEnabled() {
        let s = state()
        #expect(s.status == .listening)
        #expect(s.holdsSlot)
        #expect(!s.yieldsToPlayer)
        #expect(s.status.isActive)
    }

    @Test func pausedWhenDisabled() {
        let s = state(enabled: false)
        #expect(s.status == .paused(.disabled))
        #expect(!s.holdsSlot)
    }

    @Test func pausedAndReleasedWithoutBindings() {
        let s = state(bindings: [], player: "Spotify")
        #expect(s.status == .paused(.noBindings))
        #expect(!s.holdsSlot)
        #expect(!s.yieldsToPlayer)
    }

    @Test func accessibilityNeededOnlyForUntrustedShortcutBindings() {
        #expect(state(bindings: [Self.shortcutBinding], trusted: false).status == .accessibilityNeeded)
        #expect(state(bindings: [Self.urlBinding, Self.shortcutBinding], trusted: false).status == .accessibilityNeeded)
        #expect(state(bindings: [Self.shortcutBinding], trusted: true).status == .listening)
        #expect(state(bindings: [Self.urlBinding], trusted: false).status == .listening)
    }

    @Test func playerHasTheHeadsetWhilePlaying() {
        let s = state(player: "Spotify")
        #expect(s.status == .playerHasHeadset(player: "Spotify"))
        #expect(s.yieldsToPlayer)
        #expect(s.holdsSlot)
    }

    @Test func headsetMicBusyKeepsTheSlot() {
        let s = state(busy: Self.zoomBusy)
        #expect(s.status == .headsetMicBusy(app: "Zoom"))
        #expect(s.holdsSlot)
    }

    @Test func precedence() {
        // Disabled beats everything.
        #expect(state(enabled: false, bindings: [], busy: Self.zoomBusy).status == .paused(.disabled))
        // No Bindings beats mic busy.
        #expect(state(bindings: [], busy: Self.zoomBusy).status == .paused(.noBindings))
        #expect(state(bindings: [], headsets: []).status == .paused(.noBindings))
        // No headset beats mic busy, Accessibility and a playing player.
        #expect(state(bindings: [Self.shortcutBinding], player: "Music", busy: Self.zoomBusy, headsets: []).status == .noHeadset)
        // Mic busy beats Accessibility and a playing player.
        #expect(state(bindings: [Self.shortcutBinding], player: "Music", busy: Self.zoomBusy).status == .headsetMicBusy(app: "Zoom"))
        // Accessibility beats a playing player.
        #expect(state(bindings: [Self.shortcutBinding], player: "Music").status == .accessibilityNeeded)
    }

    @Test func onlyListeningKeepsTheIconFull() {
        let statuses: [ListenerStatus] = [
            .paused(.disabled), .paused(.noBindings), .headsetMicBusy(app: nil),
            .accessibilityNeeded, .playerHasHeadset(player: "Spotify"), .noHeadset,
        ]
        #expect(ListenerStatus.listening.isActive)
        for status in statuses { #expect(!status.isActive) }
    }

    @Test func menuTitlesMatchTheSpec() {
        #expect(ListenerStatus.listening.title == "Listening")
        #expect(ListenerStatus.paused(.disabled).title == "Paused")
        #expect(ListenerStatus.paused(.noBindings).title == "Paused")
        #expect(ListenerStatus.playerHasHeadset(player: "Spotify").title == "Player has the headset")
        #expect(ListenerStatus.headsetMicBusy(app: "Zoom").title == "Headset mic in use")
        #expect(ListenerStatus.accessibilityNeeded.title == "Accessibility needed")
        #expect(ListenerStatus.noHeadset.title == "No headset connected")
    }

    @Test func settingsLinesMatchTheSpec() {
        #expect(ListenerStatus.listening.detail == "Listening — press your AirPods")
        #expect(ListenerStatus.paused(.noBindings).detail == "Not listening: no active Bindings")
        #expect(ListenerStatus.playerHasHeadset(player: "Spotify").detail == "Not listening: Spotify is playing")
        #expect(ListenerStatus.paused(.disabled).detail == "Not listening: disabled in menu")
        #expect(ListenerStatus.headsetMicBusy(app: "Zoom").detail == "Not listening: Zoom is recording from the headset mic")
        #expect(ListenerStatus.headsetMicBusy(app: nil).detail == "Not listening: An app is recording from the headset mic")
        #expect(ListenerStatus.accessibilityNeeded.detail == "Not listening: Accessibility needed")
        #expect(ListenerStatus.noHeadset.detail == "Not listening: no headset connected")
    }
}
