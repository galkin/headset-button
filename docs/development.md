# Development reference

## Build and run

SwiftPM package (`Package.swift`, sources in `Sources/HeadsetButton/` and `Sources/HeadsetButtonCore/`, tests in `Tests/`) built with Xcode's `xcodebuild`; `scripts/build-app.sh` assembles and ad-hoc signs the `.app`. No Xcode project file; to edit in Xcode, `open Package.swift`.

```sh
scripts/build-app.sh            # Release; pass Debug for a debug build
open "build/Headset Button.app"
osascript -e 'tell application id "in.galk.HeadsetButton" to quit'
swift test
swift format format -i -r Sources Tests Package.swift   # style per .swift-format
```

- Deployment target is macOS 15: `Package.swift` and `LSMinimumSystemVersion` in `Resources/Info.plist` stay equal. CoreAudio process objects need 14.2; guard anything newer with `#available`.
- The bundle's `Info.plist` lives in `Resources/Info.plist` (`LSUIElement`, bundle id `in.galk.HeadsetButton`); edit it there, not in `build/`.
- The script signs ad-hoc with designated requirement `identifier "in.galk.HeadsetButton"`, meant to keep an Accessibility grant across rebuilds and updates. Unverified across release updates; keep the requirement when changing the script.

## Checks

`.githooks/pre-commit` lints staged Swift files with `swift format lint --strict` and runs `swift test`. Enable it in a fresh clone with `git config core.hooksPath .githooks`. CI runs the same lint over all sources.

## Testing without a Headset

The slot is held only while a Headset is connected: CoreAudio lists an alive Bluetooth/BluetoothLE device with output streams, whether or not it is the default output. A Debug build started with `open --env HEADSET_BUTTON_FAKE_HEADSET=1 "build/Headset Button.app"` treats any output device as the Headset when no Bluetooth output is connected.

## Logs

```sh
log stream --style compact --predicate 'subsystem == "in.galk.HeadsetButton"'
```

Narrow with `AND category == "<name>"`:

- `gesture`: every remote command, its `sourceID` (or "unreadable"), accepted or dropped.
- `slot`: connected Headsets, why the Now Playing slot is held or released.
- `action`: URL opened or failed, shortcut pressed, Run button, Accessibility, launch at login.
- `recorder`: the Settings shortcut recorder's event tap (created, failed, removed; captured combo; swallowed or passed through).
- `mic`: which devices count as the Headset's input, busy or free, which app records, the notification.

## Releases

- `.github/workflows/ci.yml` lints, runs `swift test` and `scripts/build-app.sh` on pushes and PRs to `main`.
- `.github/workflows/release.yml` runs on a pushed tag `v*` (`git tag -a v0.2.0 -m … && git push origin v0.2.0`): tests, builds with `VERSION` from the tag and `BUILD_NUMBER` from the run number, zips with `ditto -c -k --keepParent`, publishes a GitHub Release with generated notes. Push the tag only after CI on `main` is green.
- Both workflows pin the runner image and Xcode; bump them together when the runner images change.
- `VERSION` / `BUILD_NUMBER` set `CFBundleShortVersionString` / `CFBundleVersion` in the built app only; locally the plist values apply.
- Releases are ad-hoc signed, not notarized; `README.md` tells users how to open the app past Gatekeeper.

## App icon

`scripts/make-icon.sh` builds `Resources/AppIcon.icns` (sips + iconutil): 16, 16@2x, 32, 32@2x from `design/app-icon-small.png` (64×64, heavier strokes), the other sizes from `design/app-icon-1024.png`. Both PNGs are gitignored exports of the App icon board in `design/headset-button.pen`: re-export them before running the script. The built `.icns` is tracked.
