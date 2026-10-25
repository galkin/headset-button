import CoreAudio
import HeadsetButtonCore

/// Watches CoreAudio's device list for connected Headsets (alive Bluetooth devices with output
/// streams, default output or not), so the app holds the Now Playing slot only while one is
/// connected. It only reads properties and listens for changes; the default output plays no
/// part (spec, "Capturing Gestures").
@MainActor
final class HeadsetConnectionMonitor {
    private typealias Listener = (
        object: AudioObjectID, address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock
    )

    private let onChange: @MainActor ([Headset]) -> Void
    private let anyOutputCounts: Bool
    private(set) var headsets: [Headset] = []
    private var hasEvaluated = false
    private var systemListeners: [Listener] = []
    private var deviceListeners: [AudioObjectID: [Listener]] = [:]

    /// `anyOutputCounts`: the debug switch `HEADSET_BUTTON_FAKE_HEADSET`.
    init(anyOutputCounts: Bool = false, onChange: @escaping @MainActor ([Headset]) -> Void) {
        self.anyOutputCounts = anyOutputCounts
        self.onChange = onChange
    }

    func start() {
        // The device list changes when a Headset connects or disconnects.
        if let listener = Self.listen(
            AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices, { [weak self] in self?.evaluate() })
        {
            systemListeners.append(listener)
        }
        evaluate()
    }

    private func evaluate() {
        let ids = AudioProperty.objects(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices)
        watchDevices(ids)
        let devices = ids.map(AudioProperty.summary(ofDevice:))
        let new = HeadsetConnection.connected(from: devices, anyOutputCounts: anyOutputCounts)
        guard new != headsets || !hasEvaluated else { return }
        hasEvaluated = true
        headsets = new
        let names = new.map(\.logDescription).joined(separator: ", ")
        Log.slot.notice("Connected headsets: \(new.isEmpty ? "none" : names, privacy: .public)")
        onChange(new)
    }

    /// A device's alive state, transport type and streams can change after it appears (a
    /// Bluetooth device finishing its connection, or going away); listen on every device.
    private func watchDevices(_ ids: [AudioObjectID]) {
        let current = Set(ids)
        for (id, listeners) in deviceListeners where !current.contains(id) {
            for listener in listeners { Self.remove(listener) }
            deviceListeners[id] = nil
        }
        for id in ids where deviceListeners[id] == nil {
            let selectors: [(AudioObjectPropertySelector, AudioObjectPropertyScope)] = [
                (kAudioDevicePropertyDeviceIsAlive, kAudioObjectPropertyScopeGlobal),
                (kAudioDevicePropertyTransportType, kAudioObjectPropertyScopeGlobal),
                (kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput),
            ]
            deviceListeners[id] = selectors.compactMap { selector, scope in
                Self.listen(id, selector, scope: scope) { [weak self] in self?.evaluate() }
            }
        }
    }

    private static func listen(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        _ handler: @escaping @MainActor () -> Void
    ) -> Listener? {
        var address = AudioProperty.address(selector, scope)
        // Delivered on the main queue.
        let block: AudioObjectPropertyListenerBlock = { _, _ in MainActor.assumeIsolated { handler() } }
        let status = AudioObjectAddPropertyListenerBlock(object, &address, .main, block)
        guard status == noErr else {
            Log.slot.error(
                "Could not listen to \(AudioProperty.fourCC(selector), privacy: .public) on object \(object): \(status)"
            )
            return nil
        }
        return (object, address, block)
    }

    private static func remove(_ listener: Listener) {
        var address = listener.address
        // The device may be gone already; nothing to do then.
        _ = AudioObjectRemovePropertyListenerBlock(listener.object, &address, .main, listener.block)
    }
}
