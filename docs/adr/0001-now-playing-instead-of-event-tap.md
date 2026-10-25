# Receive headset presses as the Now Playing app, not through an event tap

An AirPods press is not an input event on macOS: it arrives as a MediaRemote command delivered only to the app that owns the system's single Now Playing slot. So the app claims that slot through `MPRemoteCommandCenter`, backed by a looping silent audio file, and receives single, double and triple press as `play`/`pause` (or `togglePlayPause`), `nextTrack` and `previousTrack`. The silent audio is deliberate, not a hack to remove.

## Considered Options

- **`CGEventTap` / `IOHIDManager`**: see keyboard media keys but never an AirPods press (probes in the airpods-keybind project, on AirPods Pro).
- **Private MediaRemote framework**: reads Now Playing state and sends commands, but cannot intercept them.

## Consequences

- An app that is actually playing audio (Spotify, Music) wins the slot back; presses then go to it, not to us.
- Owning the slot means keyboard media keys and Control Center send us the same commands. We keep only commands whose private `MPRemoteCommandEvent.sourceID` names `com.apple.bluetoothd` and drop the rest; public API carries no sender.
- While the headset microphone is in use, macOS switches it to HFP and presses become call controls that never reach the Now Playing app; single and double press were both confirmed lost (2026-10-25). Dictation that should stop from the Headset has to record from another microphone.
- Rejected workaround: holding our own mic input with `AVAudioApplication.setInputMuteStateChangeHandler` does deliver each press as a mute toggle, and stopping Dictation on it worked, but macOS always shows a mute HUD ("Microphone Off" or "Cannot Control Mic with AirPods Max") on every press. The user judged that HUD misleading enough to drop the approach (2026-10-25).
- Owning the slot puts the app in the Now Playing widget (Control Center), and no way was found to hold the slot without it (tried 2026-10-25 on macOS 27, each checked in Control Center and with a synthetic Play/Pause key, which still arrived from `com.apple.rcd` every time): `playbackState` `.playing`, `.paused`, `.stopped`, `.unknown` and `.interrupted` only change the widget's play/pause glyph; `nowPlayingInfo = nil` still shows the app's name; `nextTrack`/`previousTrack` `isEnabled = false` keeps the widget and the commands still arrive; private `MRMediaRemoteSetNowPlayingVisibility(local origin, NeverVisible)` (from WebKit's `MediaRemoteSPI.h`) and `MRMediaRemoteSetCanBeNowPlayingApplication(false)` change nothing visible. `MPNowPlayingSession` is not available on native macOS. Only quitting removes the widget ("Not Playing"). So the widget shows the app icon, `Headset Button` and `Listening for headset presses`, and the slot is held only while a Headset is connected. airpods-keybind has the same widget and only narrows when it appears (slot held while a configured app is frontmost); the user accepted the widget for v1 and deferred that narrowing to the context feature (2026-10-25).
