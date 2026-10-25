import CoreGraphics
import Testing

@testable import HeadsetButtonCore

@Suite struct ShortcutCaptureTests {
    static let space = 49
    static let keyA = 0

    @Test func superwhisperHotkeyBecomesTheStoredKeyCombo() {
        let decision = ShortcutCapture.decide(keyCode: Self.space, flags: [.maskControl, .maskAlternate, .maskCommand])
        #expect(decision == .capture(BindingTests.superwhisperHotkey))
    }

    @Test func eachModifierMapsToItsCarbonBit() {
        #expect(KeyCombo(keyCode: Self.keyA, flags: .maskCommand).carbonModifiers == KeyCombo.cmdKey)
        #expect(KeyCombo(keyCode: Self.keyA, flags: .maskShift).carbonModifiers == KeyCombo.shiftKey)
        #expect(KeyCombo(keyCode: Self.keyA, flags: .maskAlternate).carbonModifiers == KeyCombo.optionKey)
        #expect(KeyCombo(keyCode: Self.keyA, flags: .maskControl).carbonModifiers == KeyCombo.controlKey)
    }

    @Test func capsLockFnAndDeviceBitsAreIgnored() {
        let flags = CGEventFlags(
            rawValue: CGEventFlags.maskCommand.rawValue
                | CGEventFlags.maskAlphaShift.rawValue
                | CGEventFlags.maskSecondaryFn.rawValue
                | CGEventFlags.maskNonCoalesced.rawValue
                | 0x8)  // NX_DEVICELCMDKEYMASK
        #expect(
            KeyCombo(keyCode: Self.keyA, flags: flags)
                == KeyCombo(carbonKeyCode: Self.keyA, carbonModifiers: KeyCombo.cmdKey))
    }

    @Test func eventFlagsRoundTrip() {
        let flags: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
        #expect(KeyCombo(keyCode: Self.space, flags: flags).eventFlags == flags)
    }

    @Test func escapeAloneCancelsAndDeleteAloneClears() {
        #expect(ShortcutCapture.decide(keyCode: KeyCombo.escapeKeyCode, flags: []) == .cancel)
        #expect(ShortcutCapture.decide(keyCode: KeyCombo.deleteKeyCode, flags: []) == .clear)
        #expect(ShortcutCapture.decide(keyCode: KeyCombo.forwardDeleteKeyCode, flags: []) == .clear)
    }

    @Test func escapeAndDeleteWithModifiersAreShortcuts() {
        #expect(
            ShortcutCapture.decide(keyCode: KeyCombo.escapeKeyCode, flags: .maskCommand)
                == .capture(KeyCombo(carbonKeyCode: KeyCombo.escapeKeyCode, carbonModifiers: KeyCombo.cmdKey)))
        #expect(
            ShortcutCapture.decide(keyCode: KeyCombo.deleteKeyCode, flags: .maskControl)
                == .capture(KeyCombo(carbonKeyCode: KeyCombo.deleteKeyCode, carbonModifiers: KeyCombo.controlKey)))
    }

    @Test func tabAndShiftTabMoveFocus() {
        #expect(ShortcutCapture.decide(keyCode: KeyCombo.tabKeyCode, flags: []) == .moveFocus(backward: false))
        #expect(ShortcutCapture.decide(keyCode: KeyCombo.tabKeyCode, flags: .maskShift) == .moveFocus(backward: true))
        #expect(
            ShortcutCapture.decide(keyCode: KeyCombo.tabKeyCode, flags: .maskAlphaShift) == .moveFocus(backward: false))
    }

    @Test func tabWithCommandLikeModifiersIsAShortcut() {
        #expect(
            ShortcutCapture.decide(keyCode: KeyCombo.tabKeyCode, flags: .maskControl)
                == .capture(KeyCombo(carbonKeyCode: KeyCombo.tabKeyCode, carbonModifiers: KeyCombo.controlKey)))
        #expect(
            ShortcutCapture.decide(keyCode: KeyCombo.tabKeyCode, flags: [.maskShift, .maskCommand])
                == .capture(
                    KeyCombo(carbonKeyCode: KeyCombo.tabKeyCode, carbonModifiers: KeyCombo.shiftKey | KeyCombo.cmdKey)))
    }

    @Test func plainAndShiftOnlyKeysKeepRecording() {
        #expect(ShortcutCapture.decide(keyCode: Self.keyA, flags: []) == .keepRecording)
        #expect(ShortcutCapture.decide(keyCode: Self.keyA, flags: .maskShift) == .keepRecording)
        #expect(ShortcutCapture.decide(keyCode: Self.space, flags: .maskAlphaShift) == .keepRecording)
    }

    @Test func functionKeysNeedNoModifier() {
        #expect(
            ShortcutCapture.decide(keyCode: 96, flags: []) == .capture(KeyCombo(carbonKeyCode: 96, carbonModifiers: 0)))
    }

    @Test func displayStringUsesAppleModifierOrder() {
        let all = KeyCombo(keyCode: Self.space, flags: [.maskCommand, .maskShift, .maskAlternate, .maskControl])
        #expect(all.displayString(characterKeyName: nil) == "⌃⌥⇧⌘Space")
        #expect(BindingTests.superwhisperHotkey.displayString(characterKeyName: nil) == "⌃⌥⌘Space")
    }

    @Test func characterKeysUseTheLayoutNameUppercased() {
        let combo = KeyCombo(carbonKeyCode: Self.keyA, carbonModifiers: KeyCombo.cmdKey)
        #expect(combo.displayString(characterKeyName: "a") == "⌘A")
        #expect(combo.displayString(characterKeyName: nil) == "⌘Key 0")
        #expect(combo.displayString(characterKeyName: "") == "⌘Key 0")
    }
}
