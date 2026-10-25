import AppKit
import ApplicationServices
import HeadsetButtonCore

/// Runs a Binding's Action. No feedback of its own when a Gesture fires.
/// Also finds the app that opens a URL, for the Settings URL check.
@MainActor
enum ActionRunner {
    static func run(_ action: Action) {
        switch action {
        case .openURL(let url):
            // Don't activate the target app: Dictation should land in the frontmost app.
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            NSWorkspace.shared.open(url, configuration: configuration) { app, error in
                if let error {
                    Log.action.error("Open URL \(url.absoluteString, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                } else {
                    Log.action.notice("Opened \(url.absoluteString, privacy: .public) in \(app?.localizedName ?? "unknown app", privacy: .public)")
                }
            }
        case .pressShortcut(let combo):
            guard Accessibility.isTrusted else {
                Log.action.error("Press shortcut skipped: Accessibility not granted")
                return
            }
            press(combo)
            Log.action.notice("Pressed key code \(combo.carbonKeyCode) modifiers \(combo.carbonModifiers)")
        }
    }

    static func handler(for url: URL) -> URLHandler? {
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: url) else { return nil }
        return URLHandler(appName: AppName.ofApp(at: appURL), appPath: appURL.path)
    }

    private static func press(_ combo: KeyCombo) {
        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: combo.virtualKeyCode, keyDown: keyDown) else { continue }
            event.flags = combo.eventFlags
            event.post(tap: .cghidEventTap)
        }
    }
}

enum Accessibility {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt (adds the app to the Accessibility list).
    static func request() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        Log.action.notice("Requested Accessibility")
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

enum AppName {
    /// The app's name as Finder shows it, without ".app".
    static func ofApp(at url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}
