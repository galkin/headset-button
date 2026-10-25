import AppKit
import CoreAudio
import HeadsetButtonCore

/// Watches for Headset mic busy with CoreAudio, for any app. It only reads properties and
/// listens for changes; it never opens an input stream, so the app never holds the mic.
///
/// The Headset's input device usually is the same CoreAudio device as its output, which our
/// own silent loop keeps running, so `kAudioDevicePropertyDeviceIsRunningSomewhere` alone
/// cannot tell busy from free. Busy needs, in addition, another process whose input runs on
/// the Headset device (`kAudioProcessPropertyIsRunningInput` and its input-scope
/// `kAudioProcessPropertyDevices`, macOS 14.2+).
@MainActor
final class HeadsetMicMonitor {
    private let onChange: @MainActor (HeadsetMicBusy?) -> Void
    private(set) var busy: HeadsetMicBusy?

    private var headset: [AudioDeviceSummary] = []
    private var listeners:
        [(object: AudioObjectID, address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)] = []
    private var deviceListeners:
        [(object: AudioObjectID, address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)] = []
    private var processListeners:
        [AudioObjectID: [(address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)]] = [:]
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    init(onChange: @escaping @MainActor (HeadsetMicBusy?) -> Void) {
        self.onChange = onChange
    }

    func start() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        listen(system, kAudioHardwarePropertyDevices, into: &listeners) { [weak self] in self?.rescanDevices() }
        listen(system, kAudioHardwarePropertyProcessObjectList, into: &listeners) { [weak self] in
            self?.rescanProcesses()
        }
        rescanDevices()
        rescanProcesses()
    }

    // MARK: - Devices

    private func rescanDevices() {
        for listener in deviceListeners { remove(listener.object, listener.address, listener.block) }
        deviceListeners = []

        let devices = AudioProperty.objects(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices).map(
            AudioProperty.summary(ofDevice:))
        let selected = HeadsetInputDevices.select(from: devices)
        if selected.map(\.id) != headset.map(\.id) {
            let names = selected.map { "\($0.name) [\($0.id) \($0.uid)]" }.joined(separator: ", ")
            Log.mic.notice("Headset input devices: \(selected.isEmpty ? "none" : names, privacy: .public)")
        }
        headset = selected
        for device in selected {
            listen(device.id, kAudioDevicePropertyDeviceIsRunningSomewhere, into: &deviceListeners) { [weak self] in
                self?.evaluate()
            }
        }
        evaluate()
    }

    // MARK: - Processes

    private func rescanProcesses() {
        let processes = Set(
            AudioProperty.objects(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList))
        for (process, entries) in processListeners where !processes.contains(process) {
            for entry in entries { remove(process, entry.address, entry.block) }
            processListeners[process] = nil
        }
        for process in processes where processListeners[process] == nil {
            var entries:
                [(object: AudioObjectID, address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)] =
                    []
            listen(process, kAudioProcessPropertyIsRunningInput, into: &entries) { [weak self] in self?.evaluate() }
            listen(process, kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeInput, into: &entries) {
                [weak self] in self?.evaluate()
            }
            processListeners[process] = entries.map { ($0.address, $0.block) }
        }
        evaluate()
    }

    private static func summary(ofProcess process: AudioObjectID) -> AudioProcessSummary {
        AudioProcessSummary(
            pid: Int32(bitPattern: AudioProperty.uint32(process, kAudioProcessPropertyPID) ?? 0),
            bundleID: AudioProperty.string(process, kAudioProcessPropertyBundleID),
            isRunningInput: (AudioProperty.uint32(process, kAudioProcessPropertyIsRunningInput) ?? 0) != 0,
            inputDeviceIDs: AudioProperty.objects(
                process, kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeInput)
        )
    }

    // MARK: - Busy

    private func evaluate() {
        let new = currentBusy()
        guard new != busy else { return }
        busy = new
        if let new {
            Log.mic.notice(
                "Headset mic busy: \(new.appName ?? "unknown app", privacy: .public) records from \(new.headsetName, privacy: .public)"
            )
        } else {
            Log.mic.notice("Headset mic free")
        }
        onChange(new)
    }

    private func currentBusy() -> HeadsetMicBusy? {
        let running = headset.filter {
            (AudioProperty.uint32($0.id, kAudioDevicePropertyDeviceIsRunningSomewhere) ?? 0) != 0
        }
        guard !running.isEmpty else { return nil }
        let processes = AudioProperty.objects(
            AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList
        )
        .map(Self.summary(ofProcess:))
        let recorders = HeadsetMicRecorders.recording(
            processes: processes,
            headsetDeviceIDs: Set(running.map(\.id)),
            ownPID: ownPID
        )
        guard let first = recorders.first else { return nil }
        let names = recorders.map(Self.appName)
        if names.count > 1 {
            Log.mic.notice("Recording from the Headset: \(names.joined(separator: ", "), privacy: .public)")
        }
        let device = running.first { first.inputDeviceIDs.contains($0.id) } ?? running[0]
        return HeadsetMicBusy(appName: Self.appName(of: first), headsetName: device.name)
    }

    /// A regular app's own name; else the app its bundle id names; else the bundle id.
    private static func appName(of process: AudioProcessSummary) -> String {
        let running = NSRunningApplication(processIdentifier: process.pid)
        if let running, running.activationPolicy == .regular, let name = running.localizedName { return name }
        if let bundleID = process.bundleID ?? running?.bundleIdentifier {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                return AppName.ofApp(at: url)
            }
            if let name = running?.localizedName { return name }
            return bundleID
        }
        return running?.localizedName ?? "pid \(process.pid)"
    }

    // MARK: - Listeners

    private func listen(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        into list:
            inout [(
                object: AudioObjectID, address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock
            )],
        _ handler: @escaping @MainActor () -> Void
    ) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        // Delivered on the main queue.
        let block: AudioObjectPropertyListenerBlock = { _, _ in MainActor.assumeIsolated { handler() } }
        let status = AudioObjectAddPropertyListenerBlock(object, &address, .main, block)
        if status == noErr {
            list.append((object, address, block))
        } else {
            Log.mic.error(
                "Could not listen to \(AudioProperty.fourCC(selector), privacy: .public) on object \(object): \(status)"
            )
        }
    }

    private func remove(
        _ object: AudioObjectID, _ address: AudioObjectPropertyAddress,
        _ block: @escaping AudioObjectPropertyListenerBlock
    ) {
        var address = address
        // The object may be gone already; nothing to do then.
        _ = AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
    }
}

/// Reads CoreAudio properties; nil or empty when the property is missing.
enum AudioProperty {
    static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope)
        -> AudioObjectPropertyAddress
    {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = address(selector, kAudioObjectPropertyScopeGlobal)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector, kAudioObjectPropertyScopeGlobal)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, let value else {
            return nil
        }
        let string = value.takeRetainedValue() as String
        return string.isEmpty ? nil : string
    }

    static func objects(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> [AudioObjectID] {
        var address = address(selector, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    /// A device as far as finding the Headset goes.
    static func summary(ofDevice device: AudioObjectID) -> AudioDeviceSummary {
        let transport: AudioDeviceSummary.Transport =
            switch uint32(device, kAudioDevicePropertyTransportType) {
            case kAudioDeviceTransportTypeBluetooth: .bluetooth
            case kAudioDeviceTransportTypeBluetoothLE: .bluetoothLE
            default: .other
            }
        return AudioDeviceSummary(
            id: device,
            name: string(device, kAudioObjectPropertyName) ?? "Headset",
            uid: string(device, kAudioDevicePropertyDeviceUID) ?? "",
            modelUID: string(device, kAudioDevicePropertyModelUID) ?? "",
            transport: transport,
            hasInput: !objects(device, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput).isEmpty,
            hasOutput: !objects(device, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput).isEmpty,
            isAlive: (uint32(device, kAudioDevicePropertyDeviceIsAlive) ?? 0) != 0
        )
    }

    static func fourCC(_ selector: AudioObjectPropertySelector) -> String {
        let bytes = withUnsafeBytes(of: selector.bigEndian, Array.init)
        return String(bytes: bytes, encoding: .ascii) ?? String(selector)
    }
}
