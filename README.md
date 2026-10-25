# Headset Button

A macOS menu bar app that turns presses on your Bluetooth headphones into actions on your Mac. A single, double or triple press on, for example, AirPods Max can open a URL or press a keyboard shortcut instead of playing or skipping music. Presses from your keyboard's media keys and from Control Center keep working as before; only presses from the headset are taken.

The motivating use is [Superwhisper](https://superwhisper.com): press the headset once to start dictation, press again to stop it, without touching the keyboard.

## Requirements

- macOS 15 Sequoia or later.
- Bluetooth headphones whose controls send play/pause and next/previous track, such as AirPods Max. They need to be connected to the Mac; the Mac's sound does not have to play through them.

## Install

1. Download `Headset-Button-<version>.zip` from the [latest release](https://github.com/galkin/headset-button/releases/latest).
2. Unzip it and move **Headset Button.app** to `/Applications`.
3. Open it. Its icon (a key with a downward arrow) appears in the menu bar; there is no Dock icon.

### Opening an app from an unidentified developer

Releases are ad-hoc signed, not notarized by Apple, so the first launch is blocked with a warning that Apple cannot verify the app. To open it anyway, either:

- try to open the app once, then go to **System Settings → Privacy & Security**, scroll to the message about Headset Button and click **Open Anyway**; or
- remove the quarantine flag in Terminal:

  ```sh
  xattr -dr com.apple.quarantine "/Applications/Headset Button.app"
  ```

## First setup

1. Click the menu bar icon and choose **Settings…** (⌘,).
2. In the **Gestures** table, pick an **Action** for a press:
   - **Open URL**: enter a URL, for example `superwhisper://record` to toggle Superwhisper's recording. The row shows which app opens it, or a red warning if no app does.
   - **Press shortcut**: click the recorder and press the shortcut, for example Superwhisper's own toggle shortcut. The app asks for Accessibility the first time; grant it in **System Settings → Privacy & Security → Accessibility**.
3. A row applies as soon as its **State** says **Active**; there is no Save button. **Run** tries the action without the headset.
4. Press your headset. The row highlights and the footer shows `Last press: …`.

The menu also has an **Enabled** toggle to pause the app, and Settings has **Launch at login**.

## Permissions and why

- **Accessibility**: only for **Press shortcut**, to type the shortcut into other apps and to record shortcuts that other apps already own. **Open URL** needs no permission.
- **Notifications** (optional): one notification when an action you triggered starts a recording from the headset's microphone (see below).
- No microphone access. The app never records audio.

## Known limits

- **Presses are lost while any app records from the headset's microphone.** macOS switches the headset to call mode and presses become call controls. If dictation should stop from the headset, choose another microphone (for example the Mac's built-in one) in Superwhisper. The app shows `Headset mic in use` and notifies you when this happens right after one of its actions.
- **A playing Spotify or Music takes the presses.** While either actually plays, presses go to it; the app shows `Player has the headset` and takes over again when playback stops.
- **The app appears in Control Center's Now Playing widget** as "Headset Button – Listening for headset presses". This is how it receives the presses and cannot be hidden. It shows only while a Bluetooth headset is connected and at least one action is set.
- **After updating, Accessibility may need re-granting.** Ad-hoc signed builds can lose the grant when the app is replaced. If **Press shortcut** stops working, remove Headset Button from **System Settings → Privacy & Security → Accessibility** with the minus button and add it again.
- **Menu bar managers** such as Bartender or Ice may hide the icon, and the app has no other way to open Settings. If you don't see the icon, allow it in your menu bar manager.

## Troubleshooting

The status line in the menu and in Settings says why the app is not listening (no headset connected, no active actions, disabled, a player is playing, headset mic in use, Accessibility needed).

To see every press the app receives and whether it was accepted, run in Terminal:

```sh
log stream --style compact --predicate 'subsystem == "in.galk.HeadsetButton"'
```

A headset press shows as `sourceID=com.apple.bluetoothd ... decision=accepted`; keyboard media keys show as dropped. Include this output when you report a problem.

## Build from source

Requires Xcode 26 or later.

```sh
git clone https://github.com/galkin/headset-button.git
cd headset-button
swift test
scripts/build-app.sh
open "build/Headset Button.app"
```

## Privacy

Headset Button makes no network connections and collects nothing. It does not access the microphone. To tell headset presses from media keys it reads private fields of macOS's media remote events (MediaRemote) locally, and it watches CoreAudio to see which app records from the headset; none of this leaves your Mac.

## License

MIT, see [LICENSE](LICENSE).
