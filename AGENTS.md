## Build and test

```sh
scripts/build-app.sh            # builds and ad-hoc signs build/Headset Button.app
swift test
```

- Put logic in `Sources/HeadsetButtonCore` (no AppKit, SwiftUI or MediaPlayer) and test it there; `Sources/HeadsetButton` is the glue.
- Logs, the fake-Headset switch, signing, the pre-commit hook, releases and the app icon: `docs/development.md`.
- `README.md` is for people who download the app; developer details stay out of it.

## Design

All mockups live in one file, `design/headset-button.pen`: add new screens to it as frames. PNG exports in `design/` are gitignored.

## Agent skills

### Issue tracker

Issues live in GitHub Issues of `galkin/headset-button` (`gh` CLI); the v1 spec is `docs/spec-v1.md`. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
