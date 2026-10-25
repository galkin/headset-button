import HeadsetButtonCore
import SwiftUI

@main
struct HeadsetButtonApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(nsImage: model.status.isActive ? MenuBarIcon.active : MenuBarIcon.inactive)
        }

        Settings {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
    }
}

private struct MenuContent: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(model.status.title)
        Toggle("Enabled", isOn: $model.isEnabled)
        Divider()
        Button("Settings…") {
            // A menu bar app is not active; bring the Settings window to the front.
            NSApplication.shared.activate()
            openSettings()
            DispatchQueue.main.async { NSApplication.shared.activate() }
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit Headset Button") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
