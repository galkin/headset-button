import Foundation
import Testing
@testable import HeadsetButtonCore

@Suite struct URLValidationTests {
    static let superwhisper = URLHandler(appName: "superwhisper", appPath: "/Applications/superwhisper.app")

    @Test func decisionFromParseAndLookup() {
        let url = URL(string: "superwhisper://record")!
        #expect(URLValidation.decide(text: "", url: nil, handler: nil) == .empty)
        #expect(URLValidation.decide(text: "  \n", url: nil, handler: nil) == .empty)
        #expect(URLValidation.decide(text: "example.com", url: nil, handler: nil) == .notAURL)
        #expect(URLValidation.decide(text: "superwhisper://record", url: url, handler: nil) == .noApp(scheme: "superwhisper"))
        #expect(URLValidation.decide(text: "superwhisper://record", url: url, handler: Self.superwhisper) == .opens(Self.superwhisper))
    }

    @Test func parseNeedsAScheme() {
        #expect(URLValidation.parse("example.com") == nil)
        #expect(URLValidation.parse("") == nil)
        #expect(URLValidation.parse(" superwhisper://record ") == URL(string: "superwhisper://record"))
    }

    @Test func validateLooksUpOnlyParsedURLs() {
        var looked: [URL] = []
        let lookup: (URL) -> URLHandler? = { looked.append($0); return $0.scheme == "superwhisper" ? Self.superwhisper : nil }
        #expect(URLValidation.validate("not a url", lookup: lookup) == .notAURL)
        #expect(looked.isEmpty)
        #expect(URLValidation.validate("superwhishper://record", lookup: lookup) == .noApp(scheme: "superwhishper"))
        #expect(URLValidation.validate("superwhisper://record", lookup: lookup).isValid)
    }

    @Test func captions() {
        #expect(URLValidation.empty.caption == nil)
        #expect(URLValidation.noApp(scheme: "superwhishper").caption == "No app opens superwhishper://")
        #expect(URLValidation.opens(Self.superwhisper).caption == "Opens in superwhisper")
    }
}

@Suite struct RowStateTests {
    static let combo = KeyCombo(carbonKeyCode: 49, carbonModifiers: KeyCombo.cmdKey)
    static let opens = URLValidation.opens(URLHandler(appName: "superwhisper", appPath: "/x"))

    func derive(_ draft: BindingDraft, _ validation: URLValidation = .empty, trusted: Bool = true) -> RowState {
        RowState.derive(draft: draft, urlValidation: validation, isAccessibilityTrusted: trusted)
    }

    @Test func states() {
        #expect(derive(BindingDraft(kind: .none, urlText: "superwhisper://record"), Self.opens) == .none)
        #expect(derive(BindingDraft(kind: .openURL), .empty) == .incomplete)
        #expect(derive(BindingDraft(kind: .openURL, urlText: "x"), .notAURL) == .invalidURL)
        #expect(derive(BindingDraft(kind: .openURL, urlText: "a://"), .noApp(scheme: "a")) == .invalidURL)
        #expect(derive(BindingDraft(kind: .openURL, urlText: "a://"), Self.opens, trusted: false) == .active)
        #expect(derive(BindingDraft(kind: .pressShortcut)) == .incomplete)
        #expect(derive(BindingDraft(kind: .pressShortcut, shortcut: Self.combo), trusted: true) == .active)
        #expect(derive(BindingDraft(kind: .pressShortcut, shortcut: Self.combo), trusted: false) == .needsAccessibility)
    }

    @Test func titles() {
        #expect(RowState.none.title == nil)
        #expect(RowState.active.title == "Active")
        #expect(RowState.incomplete.title == "Incomplete")
        #expect(RowState.invalidURL.title == "Invalid URL")
        #expect(RowState.needsAccessibility.title == "Needs Accessibility")
    }

    @Test func rowsApplyOnlyWhenValid() {
        var set = BindingSet()
        set[.single] = BindingDraft(kind: .openURL, urlText: "superwhishper://record")
        set[.double] = BindingDraft(kind: .pressShortcut, shortcut: Self.combo)
        let rows = set.rows(isAccessibilityTrusted: false) { _ in nil }
        #expect(rows.map(\.state) == [.invalidURL, .needsAccessibility, .none])
        #expect(rows.compactMap(\.binding) == [Binding(gesture: .double, action: .pressShortcut(Self.combo))])
        // Run fires whatever parses, even an Invalid URL; never a None row.
        #expect(rows[0].runnableAction == .openURL(URL(string: "superwhishper://record")!))
        #expect(rows[2].runnableAction == nil)

        let fixed = set.rows(isAccessibilityTrusted: true) { _ in URLHandler(appName: "x", appPath: "/x") }
        #expect(fixed.compactMap(\.binding).count == 2)
    }
}
