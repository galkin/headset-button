# Headset Button v1

A personal macOS menu bar app: each **Gesture** on the **Headset** (AirPods Max) runs the **Action** of its **Binding**. The motivating use is a single press toggling Superwhisper **Dictation**. Terms as in `GLOSSARY.md`; the capture mechanism is in `docs/adr/0001-now-playing-instead-of-event-tap.md`.

Agreed with the user in a grilling session on 2026-10-25.

## Shape

- Swift + SwiftUI `MenuBarExtra`, no Dock icon (`LSUIElement`), launch at login via `SMAppService`.
- Bundle id `in.galk.HeadsetButton`, name **Headset Button**. App icon based on the A2 "Press" glyph, designed in `design/headset-button.pen`. UI language: English.
- No App Sandbox, no Mac App Store; private API is acceptable where needed. Built with Xcode (`/Applications/Xcode.app`, selected via `xcode-select`). Released publicly on GitHub as ad-hoc signed builds (no Developer ID or notarization yet), decided 2026-10-25.
- Minimum macOS 15. Changed on 2026-10-25 from "the current macOS (27)" so GitHub-hosted runners can build it and more users can run it; the code needs at least 14.2 (CoreAudio process objects).
- No dependencies. The shortcut recorder is our own: it captures through a HID event tap while recording, so it can record shortcuts other apps own, such as Superwhisper's ⌃⌥⌘Space.

## Capturing Gestures

- The app becomes the Now Playing app through `MPRemoteCommandCenter`, backed by a looping silent audio file.
- Gestures: single → `play` / `pause` / `togglePlayPause` (AirPods Max sends `play`/`pause`; verified 2026-10-25), double → `nextTrack`, triple → `previousTrack`. No other commands in v1.
- Only commands whose private `MPRemoteCommandEvent.sourceID` (read via KVC) names `com.apple.bluetoothd` count as Gestures; commands from keyboard media keys, Control Center or scripts are dropped.
- The Now Playing slot is held only while at least one Binding exists, the menu's **Enabled** toggle is on, **and** a Headset is connected: some connected Bluetooth audio device with output streams exists in CoreAudio (transport type Bluetooth/BluetoothLE; any model; keyboards and mice never qualify). Connection, not the current default output, decides: the user corrected this on 2026-10-25 ("выход звука и подключение по bluetooth это разные вещи"). Verified by hand on 2026-10-25: with AirPods connected but the Mac's output on its speakers and the slot released, pressing the AirPods launched Apple Music, so AVRCP presses reach the Mac whatever the output, and without our slot macOS's default handler starts Music. Otherwise it is released so media keys behave normally. Without a Headset the status is `No headset connected` and the icon is dimmed.
- Holding the slot makes macOS show the app in its Now Playing widget. It cannot be hidden (attempts in ADR 0001); the user accepted it for v1 on 2026-10-25. airpods-keybind only shows it less often by holding the slot while a configured app is frontmost; that narrowing belongs to the deferred context feature, not v1. While shown, it carries the app icon, title `Headset Button` and subtitle `Listening for headset presses`; its buttons arrive from Control Center and are dropped like keyboard media keys.
- Accepted limits: while Spotify or Music is actually playing, it owns the slot and gets the presses. While the **Headset mic is busy** (HFP), presses do not reach the app; choosing the recording app's microphone is the user's job.
- **Headset mic busy** is detected for any app, not just Superwhisper: watch the Headset's input device with CoreAudio (`kAudioDevicePropertyDeviceIsRunningSomewhere`) and name the recording app via CoreAudio process objects (`kAudioHardwarePropertyProcessObjectList`, `kAudioProcessPropertyIsRunningInput`, `kAudioProcessPropertyBundleID`, macOS 14.2+). Behaviour on AirPods Max is unverified: confirm by hand. While busy, the status is `Headset mic in use` and the menu bar icon is dimmed.
- If the Headset mic becomes busy within ~1 s after an Action ran, post one notification: `<App> records from <Headset> — stop it from the keyboard`. Our own app never holds the mic.

## Actions

- Per Gesture: **None**, **Open URL** (`NSWorkspace.open`, e.g. `superwhisper://record`) or **Press shortcut** (synthetic `CGEvent` keystroke, e.g. Superwhisper's ⌃⌥⌘Space).
- No Bindings exist on first launch.
- Accessibility is requested the first time a Press shortcut Binding is saved; Open URL needs no permission.
- No feedback in the menu bar when a Gesture fires (the Settings window shows it; see UI).

## UI

- **Menu bar icon**: option A2 "Press" from the design (side view of a key with a downward chevron), as a template image; every state but Listening (Paused, No headset connected, Accessibility needed, …) is the same glyph dimmed.
- **Menu**: status line (`Listening` / `Paused` / `No headset connected` / `Player has the headset` / `Headset mic in use` / `Accessibility needed`), `Enabled` toggle, `Settings…` (⌘,), `Quit Headset Button` (⌘Q).
- **Settings window**: one window, no tabs. Revised 2026-10-25 after the first hands-on test: the grouped rows read as confusing.
  - **Overall status** at the top, the menu's status plus its reason: `Listening — press your AirPods`, `Not listening: no active Bindings`, `Not listening: Spotify is playing`, `Not listening: disabled in menu`, `Not listening: no headset connected`, `Not listening: <App> is recording from the headset mic`, `Not listening: Accessibility needed`.
  - **Gestures table**: one row per Gesture; columns **Gesture** | **Action** (None / Open URL / Press shortcut) | **Value** (URL field or shortcut recorder, by Action) | **State** | **Run**.
    - **State**: `Active`, `Incomplete`, `Invalid URL`, `Needs Accessibility`. A row applies the moment it is valid; there is no Save button.
    - **URL validation**: the URL must parse with a scheme, and some app must open that scheme (`NSWorkspace.urlForApplication(toOpen:)`). Show `Opens in <App>` with the app's icon, or `No app opens <scheme>://` in red.
    - **Run** fires the row's Action without the Headset, to test the Action alone.
    - When a Gesture arrives, its row highlights briefly and a footer shows `Last press: Single, 3 s ago`. This feedback lives only in the Settings window; the menu bar icon stays still.
  - **General**: Launch at login.
  - **Permissions**: shown only when a Press shortcut Binding exists; Accessibility status with the caption "Required to press keyboard shortcuts in other apps." and `Open System Settings…`.
- Bindings persist in `UserDefaults`.
- Mockups: `design/headset-button.pen`.

## First step: probe on the real AirPods Max

Done 2026-10-25 on the user's AirPods Max: all three facts confirmed (single press arrives as `play`/`pause`, see Capturing Gestures). The facts were:

1. Single, double and triple press on AirPods Max arrive as `togglePlayPause` / `nextTrack` / `previousTrack` (prior probes were on AirPods Pro).
2. `superwhisper://record` toggles Dictation both ways (start and stop).
3. `sourceID` is readable via KVC and distinguishes `com.apple.bluetoothd` from `com.apple.rcd`. If it is not, fall back to accepting every source and tell the user.

## Out of scope for v1

Context-dependent behaviour (per frontmost app, including holding the Now Playing slot only while chosen apps are frontmost, which would also hide the widget elsewhere), all other `MPRemoteCommandCenter` commands, recording a Gesture to create a Binding, identifying the specific Bluetooth device, passthrough to a media player, pausing music during Dictation.
