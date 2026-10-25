## Build and run

SwiftPM package (`Package.swift`, sources in `Sources/HeadsetButton/` and `Sources/HeadsetButtonCore/`, tests in `Tests/`) built with Xcode's `xcodebuild`; `scripts/build-app.sh` assembles and ad-hoc signs the `.app`. No Xcode project file. Deployment target macOS 15 (`Package.swift` and `LSMinimumSystemVersion` in `Resources/Info.plist`; keep them equal); CoreAudio process objects need 14.2, so guard any newer API with `#available`.

```sh
scripts/build-app.sh            # Release; pass Debug for a debug build
open "build/Headset Button.app"
osascript -e 'tell application id "in.galk.HeadsetButton" to quit'
swift test                      # unit tests for the pure logic in Sources/HeadsetButtonCore
scripts/make-icon.sh            # Resources/AppIcon.icns (sips + iconutil): 16, 16@2x, 32, 32@2x from design/app-icon-small.png (64×64, heavier strokes), the other sizes from design/app-icon-1024.png
```

The slot is held only while a Headset is connected: CoreAudio lists an alive Bluetooth/BluetoothLE device with output streams, whether or not it is the default output. To test it without a Headset, run a Debug build with `open --env HEADSET_BUTTON_FAKE_HEADSET=1 "build/Headset Button.app"` (when no Bluetooth output is connected, any output device then counts as the Headset).

Watch every remote command the app receives (Gesture, `sourceID` or "unreadable", accepted or dropped):

```sh
log stream --style compact --predicate 'subsystem == "in.galk.HeadsetButton" AND category == "gesture"'
```

Drop the `AND category == …` part to also see the Now Playing slot (`slot`: connected Headsets, why the slot is held or released), Actions (`action`: opened or failed, pressed, Run button, Accessibility, launch at login), the Settings shortcut recorder's event tap (`recorder`: tap created/failed/removed, captured combo, swallowed or passed through) and Headset mic busy (`mic`: which devices count as the Headset's input, busy or free and which app records, the notification).

- `Sources/HeadsetButtonCore` holds the logic without AppKit, SwiftUI or MediaPlayer (Bindings and their storage, Gesture mapping, the `sourceID` filter, status); `Sources/HeadsetButton` is the glue. Put new logic in Core and test it there.
- The bundle's `Info.plist` lives in `Resources/Info.plist` (`LSUIElement`, bundle id `in.galk.HeadsetButton`); edit it there, not in `build/`.
- The script signs ad-hoc with designated requirement `identifier "in.galk.HeadsetButton"` so an Accessibility grant survives rebuilds. Keep that when changing the script.
- To edit in Xcode: `open Package.swift`.

## Releases

- `.github/workflows/ci.yml` runs `swift test` and `scripts/build-app.sh` on pushes and PRs to `main`.
- `.github/workflows/release.yml` runs on a pushed tag `v*` (e.g. `git tag v0.2.0 && git push origin v0.2.0`): tests, builds with `VERSION` from the tag and `BUILD_NUMBER` from the run number, zips the app with `ditto -c -k --keepParent` and publishes a GitHub Release with generated notes. Both pin the runner image and Xcode; bump them together when the runner images change.
- `VERSION` / `BUILD_NUMBER` set `CFBundleShortVersionString` / `CFBundleVersion` in the built app only; locally the plist values apply.
- Releases are ad-hoc signed, not notarized; `README.md` tells users how to open the app past Gatekeeper. The README tells users that Accessibility may need re-granting after an update (remove and re-add the app if Press shortcut stops working).
- `README.md` is for people who download the app; developer details stay here.

## Design

All mockups live in one file, `design/headset-button.pen`: add new screens to it as frames. PNG exports in `design/` are gitignored, including the two icon exports `scripts/make-icon.sh` reads: re-export them from the App icon board before running it. The built `Resources/AppIcon.icns` is tracked.

## Agent skills

### Issue tracker

Issues live in GitHub Issues of `galkin/headset-button` (`gh` CLI); the v1 spec is `docs/spec-v1.md`. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
