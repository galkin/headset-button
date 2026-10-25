import Testing

@testable import HeadsetButtonCore

@Suite struct ShortcutRecorderStateTests {
    @Test func threeDisplayStates() {
        let combo = BindingTests.superwhisperHotkey
        #expect(RecorderDisplay(combo: nil, isRecording: false) == .empty)
        #expect(RecorderDisplay(combo: nil, isRecording: true) == .recording)
        #expect(RecorderDisplay(combo: combo, isRecording: true) == .recording)
        #expect(RecorderDisplay(combo: combo, isRecording: false) == .set(combo))
    }

    @Test func onlyASetShortcutShowsTheClearButton() {
        #expect(!RecorderDisplay.empty.showsClearButton)
        #expect(!RecorderDisplay.recording.showsClearButton)
        #expect(RecorderDisplay.set(BindingTests.superwhisperHotkey).showsClearButton)
    }

    @Test func clickOnTheRecorderOrTabStartsRecording() {
        #expect(RecorderFocusCause.mouseDown(insideRecorder: true).startsRecording)
        #expect(RecorderFocusCause.keyDown(keyCode: KeyCombo.tabKeyCode).startsRecording)
        #expect(RecorderFocusCause.tabFromRecorder.startsRecording)
    }

    @Test func focusThatTheUserDidNotAimAtTheRecorderDoesNotRecord() {
        #expect(!RecorderFocusCause.mouseDown(insideRecorder: false).startsRecording)
        #expect(!RecorderFocusCause.keyDown(keyCode: 36).startsRecording)
        #expect(!RecorderFocusCause.other.startsRecording)
    }
}
