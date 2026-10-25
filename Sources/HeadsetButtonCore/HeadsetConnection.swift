/// A connected Headset: a Bluetooth audio device with output, as CoreAudio lists it.
public struct Headset: Equatable, Sendable {
    public var id: UInt32
    public var name: String
    public var transport: AudioDeviceSummary.Transport

    public init(id: UInt32, name: String, transport: AudioDeviceSummary.Transport) {
        self.id = id
        self.name = name
        self.transport = transport
    }

    /// For the `slot` log.
    public var logDescription: String {
        let kind = switch transport {
        case .bluetooth: "Bluetooth"
        case .bluetoothLE: "Bluetooth LE"
        case .other: "not Bluetooth"
        }
        return "\(name) [\(id), \(kind)]"
    }
}

/// Decides whether a Headset is connected. Connection, not the default output, decides
/// (spec, "Capturing Gestures"): AirPods can be connected while the Mac plays through its
/// speakers.
public enum HeadsetConnection {
    /// Every alive Bluetooth (Classic or LE) device with output streams, any model, whether or
    /// not it is the default output. Keyboards and mice have no output streams, so they never
    /// qualify; an input-only Bluetooth device does not either.
    ///
    /// `anyOutputCounts` is the debug switch `HEADSET_BUTTON_FAKE_HEADSET`: when no Bluetooth
    /// device qualifies, every alive output device counts as a Headset.
    public static func connected(from devices: [AudioDeviceSummary], anyOutputCounts: Bool = false) -> [Headset] {
        let outputs = devices.filter { $0.isAlive && $0.hasOutput }
        let bluetooth = outputs.filter(\.isBluetooth)
        return (bluetooth.isEmpty && anyOutputCounts ? outputs : bluetooth)
            .map { Headset(id: $0.id, name: $0.name, transport: $0.transport) }
    }
}
