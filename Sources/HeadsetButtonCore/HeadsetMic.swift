import Foundation

/// Headset mic busy: some app records from the Headset's microphone.
public struct HeadsetMicBusy: Equatable, Sendable {
    /// The recording app's name, or nil when CoreAudio does not name one.
    public var appName: String?
    /// The Headset's name as CoreAudio reports it, e.g. "Nikita’s AirPods Max".
    public var headsetName: String

    public init(appName: String?, headsetName: String) {
        self.appName = appName
        self.headsetName = headsetName
    }
}

/// A CoreAudio device as far as finding the Headset goes.
public struct AudioDeviceSummary: Equatable, Sendable {
    public enum Transport: Equatable, Sendable { case bluetooth, bluetoothLE, other }

    public var id: UInt32
    public var name: String
    public var uid: String
    public var modelUID: String
    public var transport: Transport
    public var hasInput: Bool
    public var hasOutput: Bool
    /// `kAudioDevicePropertyDeviceIsAlive`: false while a device is going away.
    public var isAlive: Bool

    public init(
        id: UInt32, name: String, uid: String, modelUID: String, transport: Transport,
        hasInput: Bool, hasOutput: Bool, isAlive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.uid = uid
        self.modelUID = modelUID
        self.transport = transport
        self.hasInput = hasInput
        self.hasOutput = hasOutput
        self.isAlive = isAlive
    }

    var isBluetooth: Bool { transport != .other }
    var mentionsAirPods: Bool {
        name.localizedCaseInsensitiveContains("AirPods") || modelUID.localizedCaseInsensitiveContains("AirPods")
    }
    /// Bluetooth device UIDs start with the device's address ("AA-BB-CC-DD-EE-FF:input").
    var bluetoothAddress: String? {
        let prefix = uid.prefix(17)
        let parts = prefix.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 6, parts.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isHexDigit) }) else { return nil }
        return prefix.uppercased()
    }
}

/// Picks the Headset's input device(s) out of all CoreAudio devices. The default input is not
/// consulted: a recording app may pick any device.
public enum HeadsetInputDevices {
    /// Bluetooth input devices that are the connected AirPods (by name or model). Failing that,
    /// Bluetooth input devices that belong to a Bluetooth headset with output (same device, or
    /// an output device with the same Bluetooth address); an input-only Bluetooth device such
    /// as a remote microphone is not a Headset.
    public static func select(from devices: [AudioDeviceSummary]) -> [AudioDeviceSummary] {
        let inputs = devices.filter { $0.isBluetooth && $0.hasInput }
        let airPods = inputs.filter(\.mentionsAirPods)
        if !airPods.isEmpty { return airPods }
        let outputAddresses = Set(devices.filter { $0.isBluetooth && $0.hasOutput }.compactMap(\.bluetoothAddress))
        return inputs.filter { $0.hasOutput || ($0.bluetoothAddress.map(outputAddresses.contains) ?? false) }
    }
}

/// A CoreAudio process object, as far as Headset mic busy goes.
public struct AudioProcessSummary: Equatable, Sendable {
    public var pid: Int32
    public var bundleID: String?
    public var isRunningInput: Bool
    /// The devices the process does input on.
    public var inputDeviceIDs: [UInt32]

    public init(pid: Int32, bundleID: String?, isRunningInput: Bool, inputDeviceIDs: [UInt32]) {
        self.pid = pid
        self.bundleID = bundleID
        self.isRunningInput = isRunningInput
        self.inputDeviceIDs = inputDeviceIDs
    }
}

public enum HeadsetMicRecorders {
    /// The processes, other than our own, that record from one of `headsetDeviceIDs`.
    public static func recording(
        processes: [AudioProcessSummary],
        headsetDeviceIDs: Set<UInt32>,
        ownPID: Int32
    ) -> [AudioProcessSummary] {
        processes.filter { process in
            process.pid != ownPID
                && process.isRunningInput
                && process.inputDeviceIDs.contains(where: headsetDeviceIDs.contains)
        }
    }
}

/// The one notification after an Action: an Action ran and the Headset mic became busy soon
/// after, so the Action most likely started a recording from the Headset mic, and the Headset
/// can no longer stop it.
public struct MicBusyNotificationRule: Sendable {
    /// "Within ~1 s" (spec); a little slack for the recording app to start its input.
    public static let window: TimeInterval = 1.5

    private var lastActionAt: Date?
    private var isBusy = false

    public init() {}

    public mutating func actionRan(at date: Date) {
        lastActionAt = date
    }

    /// Feeds a Headset mic busy reading; true when the notification should be posted now.
    /// Only a change from free to busy counts, and each Action yields at most one notification.
    public mutating func micBusyChanged(_ busy: Bool, at date: Date) -> Bool {
        defer { isBusy = busy }
        guard busy, !isBusy, let actionAt = lastActionAt else { return false }
        let elapsed = date.timeIntervalSince(actionAt)
        guard elapsed >= 0, elapsed <= Self.window else { return false }
        lastActionAt = nil
        return true
    }

    public static func body(for busy: HeadsetMicBusy) -> String {
        "\(busy.appName ?? "An app") records from \(busy.headsetName) — stop it from the keyboard"
    }
}

/// The Settings footer after a Gesture arrived: "Last press: Single, 3 s ago".
public enum LastPressText {
    public static func text(gesture: Gesture, elapsed: TimeInterval) -> String {
        "Last press: \(gesture.shortTitle), \(ago(elapsed))"
    }

    static func ago(_ elapsed: TimeInterval) -> String {
        let seconds = max(0, Int(elapsed.rounded(.down)))
        switch seconds {
        case 0: return "just now"
        case ..<60: return "\(seconds) s ago"
        case ..<3600: return "\(seconds / 60) min ago"
        default: return "\(seconds / 3600) h ago"
        }
    }
}
