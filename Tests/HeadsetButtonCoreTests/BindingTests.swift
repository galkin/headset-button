import CoreGraphics
import Foundation
import Testing

@testable import HeadsetButtonCore

@Suite struct BindingTests {
    static let superwhisperHotkey = KeyCombo(
        carbonKeyCode: 49,  // Space
        carbonModifiers: KeyCombo.controlKey | KeyCombo.optionKey | KeyCombo.cmdKey
    )

    @Test func noBindingsOnFirstLaunch() {
        let set = BindingStore.decode(nil)
        #expect(set.bindings.isEmpty)
        #expect(set[.single] == BindingDraft())
    }

    @Test func corruptDataDecodesToNoBindings() {
        #expect(BindingStore.decode(Data("not json".utf8)).bindings.isEmpty)
    }

    @Test func roundTripsThroughJSON() {
        var set = BindingSet()
        set[.single] = BindingDraft(kind: .openURL, urlText: "superwhisper://record")
        set[.double] = BindingDraft(kind: .pressShortcut, shortcut: Self.superwhisperHotkey)
        set[.triple] = BindingDraft(kind: .none, urlText: "kept://while-none")
        #expect(BindingStore.decode(BindingStore.encode(set)) == set)
    }

    @Test func storedJSONUsesGestureNamesAsKeys() throws {
        var set = BindingSet()
        set[.single] = BindingDraft(kind: .openURL, urlText: "superwhisper://record")
        let json = try #require(String(data: BindingStore.encode(set), encoding: .utf8))
        #expect(json.contains("\"single\""))
        #expect(json.contains("\"openURL\""))
    }

    @Test func draftsBecomeBindingsOnlyWhenComplete() {
        #expect(BindingDraft(kind: .none, urlText: "superwhisper://record").action == nil)
        #expect(BindingDraft(kind: .openURL, urlText: "").action == nil)
        #expect(BindingDraft(kind: .openURL, urlText: "example.com").action == nil)
        #expect(BindingDraft(kind: .pressShortcut).action == nil)
        #expect(
            BindingDraft(kind: .openURL, urlText: "  superwhisper://record \n").action
                == .openURL(URL(string: "superwhisper://record")!)
        )
        #expect(
            BindingDraft(kind: .pressShortcut, shortcut: Self.superwhisperHotkey).action
                == .pressShortcut(Self.superwhisperHotkey)
        )
    }

    @Test func pressShortcutKindVersusBinding() {
        var set = BindingSet()
        set[.single] = BindingDraft(kind: .pressShortcut)
        #expect(set.hasPressShortcutKind)
        #expect(!set.hasPressShortcutBinding)
        set[.single].shortcut = Self.superwhisperHotkey
        #expect(set.hasPressShortcutBinding)
        #expect(set.bindings == [Binding(gesture: .single, action: .pressShortcut(Self.superwhisperHotkey))])
    }

    @Test func carbonModifiersMapToEventFlags() {
        let flags = Self.superwhisperHotkey.eventFlags
        #expect(flags.contains(.maskControl))
        #expect(flags.contains(.maskAlternate))
        #expect(flags.contains(.maskCommand))
        #expect(!flags.contains(.maskShift))
        #expect(Self.superwhisperHotkey.virtualKeyCode == 49)
        #expect(KeyCombo(carbonKeyCode: 0, carbonModifiers: KeyCombo.shiftKey).eventFlags == .maskShift)
    }

    @Test func storePersistsInUserDefaults() throws {
        let suite = "in.galk.HeadsetButton.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = BindingStore(defaults: defaults)

        #expect(store.isEnabled)
        #expect(!store.accessibilityRequested)
        #expect(store.loadBindings().bindings.isEmpty)

        var set = BindingSet()
        set[.triple] = BindingDraft(kind: .openURL, urlText: "superwhisper://record")
        store.saveBindings(set)
        store.isEnabled = false
        store.accessibilityRequested = true

        let reloaded = BindingStore(defaults: defaults)
        #expect(reloaded.loadBindings() == set)
        #expect(!reloaded.isEnabled)
        #expect(reloaded.accessibilityRequested)
    }
}
