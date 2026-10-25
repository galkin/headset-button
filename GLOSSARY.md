# Headset Button

A macOS menu bar app that turns presses on the user's headset into actions on the Mac. The first use is toggling Superwhisper dictation.

## Language

**Headset**:
A Bluetooth audio device connected to the Mac, whose controls the app listens to, whether or not the Mac's sound currently plays through it; for example AirPods Max.
_Avoid_: Earphones, AirPods (when the model matters), device

**Gesture**:
One kind of headset press the app can tell apart: single, double or triple press. The same media command from a keyboard media key or Control Center is not a Gesture.
_Avoid_: Click, tap, button

**Action**:
What the app does on the Mac in response to a Gesture: open a URL or press a keyboard shortcut.
_Avoid_: Command, handler, macro

**Binding**:
The user's chosen pairing of one Gesture with one Action.
_Avoid_: Mapping, keymap, hotkey

**Headset mic busy**:
The state in which some app records from the Headset's microphone; Gestures cannot reach the app until it stops.
_Avoid_: HFP, call mode, mic lock

**Dictation**:
One Superwhisper recording, started and stopped by Superwhisper's own toggle; the app only fires that toggle.
_Avoid_: Recording session, transcription, voice input
