import AppKit
import Carbon.HIToolbox
import HeadsetButtonCore
import Observation

/// Records a shortcut through a keyboard event tap at the HID level, installed only while
/// a recorder is recording. The tap sees the key before it is matched against other apps'
/// global hot keys (e.g. Superwhisper's ⌃⌥⌘Space), so the recorder can capture and swallow
/// it. While recording it swallows every key-down, so nothing types into another field.
/// One recorder records at a time.
@MainActor
@Observable
final class ShortcutRecording {
    static let shared = ShortcutRecording()

    /// How the recording recorder hears back.
    struct Callbacks {
        /// The captured combo, or nil for Delete (clear).
        var onResult: (KeyCombo?) -> Void
        /// Tab (`backward` false) or Shift-Tab: recording has ended; move keyboard focus.
        var onMoveFocus: (_ backward: Bool) -> Void
        /// Recording ended, for any reason (after `onResult`, before `onMoveFocus`).
        var onEnd: () -> Void
    }

    /// The recorder that is recording, if any.
    private(set) var activeID: UUID?
    /// Why the last attempt to record could not start, per recorder.
    private(set) var failure: (id: UUID, message: String)?

    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var callbacks: Callbacks?
    /// After a capture the tap stays until this key's key-up, which it swallows too.
    @ObservationIgnored private var pendingKeyUp: Int?
    @ObservationIgnored private var resignObserver: NSObjectProtocol?

    private init() {}

    /// Starts recording for `id`; false if the event tap could not be created (see `failure`).
    /// Esc, Tab, `stop(reason:)` or the app losing focus end recording without a result.
    @discardableResult
    func start(id: UUID, callbacks: Callbacks) -> Bool {
        if activeID != nil { stop(reason: "another recorder started") }
        removeTap()
        failure = nil

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: shortcutTapCallback,
            userInfo: nil
        ) else {
            let trusted = Accessibility.isTrusted
            let message = trusted
                ? "Can't record: macOS refused the keyboard event tap."
                : "Can't record: Headset Button needs Accessibility."
            Log.recorder.error("""
                Event tap failed: accessibility=\(trusted, privacy: .public) \
                inputMonitoring=\(CGPreflightListenEventAccess(), privacy: .public)
                """)
            failure = (id, message)
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = source
        self.callbacks = callbacks
        activeID = id
        pendingKeyUp = nil
        Log.recorder.notice("""
            Event tap created (HID, head insert); recording. \
            secureInput=\(IsSecureEventInputEnabled(), privacy: .public)
            """)

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { ShortcutRecording.shared.stop(reason: "app lost focus") }
        }
        return true
    }

    /// Ends recording without changing the shortcut.
    func stop(reason: String) {
        guard activeID != nil else { return }
        Log.recorder.notice("Recording ended: \(reason, privacy: .public)")
        finishRecording()
        removeTap()
    }

    // MARK: - Tap

    /// Returns true to swallow the event.
    fileprivate func handle(type: CGEventType, keyCode: Int, flags: CGEventFlags) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            let why = type == .tapDisabledByTimeout ? "timeout" : "user input"
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
                Log.recorder.error("Event tap disabled by \(why, privacy: .public); re-enabled")
            }
            return false
        case .keyUp:
            guard let pending = pendingKeyUp, pending == keyCode else { return false }
            Log.recorder.notice("Swallowed key-up of key code \(keyCode); removing event tap")
            removeTap()
            return true
        case .keyDown:
            break
        default:
            return false
        }

        // Captured, waiting for its key-up: swallow its auto-repeats, pass everything else.
        if pendingKeyUp != nil {
            return pendingKeyUp == keyCode
        }
        guard activeID != nil else { return false }

        let combo = KeyCombo(keyCode: keyCode, flags: flags)
        let name = combo.displayString(characterKeyName: KeyNames.character(for: keyCode))
        switch ShortcutCapture.decide(keyCode: keyCode, flags: flags) {
        case .capture(let captured):
            Log.recorder.notice("""
                Captured \(name, privacy: .public) (key code \(captured.carbonKeyCode), \
                modifiers \(captured.carbonModifiers)); swallowed
                """)
            callbacks?.onResult(captured)
            finishRecording()
            pendingKeyUp = keyCode
            // Safety net: never leave the tap in place if the key-up is missed.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, self.pendingKeyUp == keyCode, self.activeID == nil else { return }
                Log.recorder.notice("No key-up within 3 s; removing event tap")
                self.removeTap()
            }
            return true
        case .clear:
            Log.recorder.notice("Delete: shortcut cleared; swallowed")
            callbacks?.onResult(nil)
            finishRecording()
            pendingKeyUp = keyCode
            return true
        case .cancel:
            Log.recorder.notice("Esc: recording cancelled; swallowed")
            finishRecording()
            pendingKeyUp = keyCode
            return true
        case .moveFocus(let backward):
            Log.recorder.notice("\(backward ? "Shift-Tab" : "Tab", privacy: .public): recording ended, moving focus; swallowed")
            let onMoveFocus = callbacks?.onMoveFocus
            finishRecording()
            pendingKeyUp = keyCode
            onMoveFocus?(backward)
            return true
        case .keepRecording:
            Log.recorder.notice("Ignored \(name, privacy: .public) (not a shortcut); swallowed, still recording")
            return true
        }
    }

    private func finishRecording() {
        let onEnd = callbacks?.onEnd
        activeID = nil
        callbacks = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        onEnd?()
    }

    private func removeTap() {
        pendingKeyUp = nil
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        runLoopSource = nil
        Log.recorder.notice("Event tap removed")
    }
}

/// The tap runs on the main run loop, so the callback is on the main thread.
private let shortcutTapCallback: CGEventTapCallBack = { _, type, event, _ in
    let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags
    let swallow = MainActor.assumeIsolated {
        ShortcutRecording.shared.handle(type: type, keyCode: keyCode, flags: flags)
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}

/// The character a key types on the current ASCII-capable layout, for showing a shortcut.
enum KeyNames {
    static func character(for keyCode: Int) -> String? {
        guard
            let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
            let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layoutData.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return OSStatus(paramErr) }
            return UCKeyTranslate(
                layout, UInt16(truncatingIfNeeded: keyCode), UInt16(kUCKeyActionDisplay), 0,
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState, characters.count, &length, &characters
            )
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}
