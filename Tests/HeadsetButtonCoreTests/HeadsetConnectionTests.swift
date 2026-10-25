import Testing

@testable import HeadsetButtonCore

@Suite struct HeadsetConnectionTests {
    static func device(
        _ id: UInt32, _ name: String, _ transport: AudioDeviceSummary.Transport,
        input: Bool = false, output: Bool = true, alive: Bool = true
    ) -> AudioDeviceSummary {
        AudioDeviceSummary(
            id: id, name: name, uid: "uid-\(id)", modelUID: "", transport: transport, hasInput: input,
            hasOutput: output, isAlive: alive)
    }

    static let speakers = device(1, "MacBook Pro Speakers", .other)
    static let mic = device(2, "MacBook Pro Microphone", .other, input: true, output: false)
    static let airPods = device(42, "AirPods Max", .bluetooth, input: true)

    @Test func aConnectedBluetoothOutputIsAHeadsetWhateverTheDefaultOutput() {
        // The device list carries no default-output fact: AirPods count while the Mac plays
        // through its speakers.
        #expect(
            HeadsetConnection.connected(from: [Self.speakers, Self.mic, Self.airPods])
                == [Headset(id: 42, name: "AirPods Max", transport: .bluetooth)])
    }

    @Test func bluetoothLEQualifies() {
        let beats = Self.device(7, "Beats", .bluetoothLE)
        #expect(HeadsetConnection.connected(from: [beats]).map(\.id) == [7])
    }

    @Test func noBluetoothOutputMeansNoHeadset() {
        #expect(HeadsetConnection.connected(from: [Self.speakers, Self.mic]).isEmpty)
        #expect(HeadsetConnection.connected(from: []).isEmpty)
    }

    @Test func bluetoothWithoutOutputStreamsDoesNotQualify() {
        // A keyboard or mouse never shows up with output streams; an input-only remote mic neither.
        let remoteMic = Self.device(9, "Remote Mic", .bluetooth, input: true, output: false)
        #expect(HeadsetConnection.connected(from: [remoteMic]).isEmpty)
    }

    @Test func aDeviceGoingAwayDoesNotQualify() {
        let leaving = Self.device(42, "AirPods Max", .bluetooth, alive: false)
        #expect(HeadsetConnection.connected(from: [Self.speakers, leaving]).isEmpty)
    }

    @Test func everyConnectedHeadsetIsListed() {
        let beats = Self.device(7, "Beats", .bluetoothLE)
        #expect(
            HeadsetConnection.connected(from: [Self.airPods, Self.speakers, beats]).map(\.name) == [
                "AirPods Max", "Beats",
            ])
    }

    @Test func fakeHeadsetSwitchCountsAnyAliveOutputOnlyWithoutARealOne() {
        #expect(HeadsetConnection.connected(from: [Self.speakers, Self.mic], anyOutputCounts: true).map(\.id) == [1])
        #expect(
            HeadsetConnection.connected(from: [Self.speakers, Self.airPods], anyOutputCounts: true).map(\.id) == [42])
        #expect(HeadsetConnection.connected(from: [Self.mic], anyOutputCounts: true).isEmpty)
    }

    @Test func logDescription() {
        #expect(
            Headset(id: 42, name: "AirPods Max", transport: .bluetooth).logDescription == "AirPods Max [42, Bluetooth]")
        #expect(Headset(id: 7, name: "Beats", transport: .bluetoothLE).logDescription == "Beats [7, Bluetooth LE]")
    }
}
