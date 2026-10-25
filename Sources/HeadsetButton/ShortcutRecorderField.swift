import AppKit
import HeadsetButtonCore
import SwiftUI

/// A shortcut recorder for the Settings Gestures table, plus the reason recording could not
/// start (Accessibility). `title` is its accessibility label. The control itself is
/// `ShortcutRecorderView`.
struct ShortcutRecorderField: View {
    let title: String
    @SwiftUI.Binding var combo: KeyCombo?
    @State private var id = UUID()

    private var failure: String? {
        guard let failure = ShortcutRecording.shared.failure, failure.id == id else { return nil }
        return failure.message
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ShortcutRecorderControl(id: id, title: title, combo: $combo)
                // Fill the table's Value column like the URL field does.
                .frame(maxWidth: .infinity, minHeight: ShortcutRecorderView.size.height, maxHeight: ShortcutRecorderView.size.height)
                // An NSView has no text baseline for SwiftUI; give the row's
                // `.firstTextBaseline` alignment the label's baseline instead of the view's bottom.
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            if let failure {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                if !Accessibility.isTrusted {
                    Button("Open System Settings…") { Accessibility.openSystemSettings() }
                        .controlSize(.small)
                }
            }
        }
    }
}

private struct ShortcutRecorderControl: NSViewRepresentable {
    let id: UUID
    let title: String
    @SwiftUI.Binding var combo: KeyCombo?

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView(recorderID: id)
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: ShortcutRecorderView, context: Context) {
        view.title = title
        view.combo = combo
        view.onChange = { combo = $0 }
    }

    static func dismantleNSView(_ view: ShortcutRecorderView, coordinator: ()) {
        view.stopRecording(reason: "recorder removed")
    }
}

/// The recorder control, following the usual macOS recorder conventions: it takes keyboard
/// focus (click or Tab) and records while it has it, with the system focus ring. Losing focus
/// (click elsewhere, Tab, the window resigning key or closing) stops recording. Keys are read
/// by `ShortcutRecording`'s HID event tap, which swallows them all while recording; Tab and
/// Shift-Tab move focus, Esc cancels, Delete clears.
final class ShortcutRecorderView: NSView {
    static let size = NSSize(width: 140, height: 22)
    private static let cornerRadius: CGFloat = 6

    /// Set while focus moves by Tab out of a recorder, whose tap swallowed the Tab key.
    private static var isTabbingFromRecorder = false

    let recorderID: UUID
    var title = "" { didSet { setAccessibilityLabel(title) } }
    var combo: KeyCombo? { didSet { if combo != oldValue { refresh() } } }
    var onChange: ((KeyCombo?) -> Void)?

    private var isRecording = false { didSet { if isRecording != oldValue { refresh() } } }
    private var display: RecorderDisplay { RecorderDisplay(combo: combo, isRecording: isRecording) }

    private let label = NSTextField(labelWithString: "")
    private let clearButton = NSButton()
    private var windowObserver: NSObjectProtocol?

    init(recorderID: UUID) {
        self.recorderID = recorderID
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        focusRingType = .default

        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        addSubview(label)

        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Clear shortcut")
        clearButton.isBordered = false
        clearButton.imagePosition = .imageOnly
        clearButton.contentTintColor = .secondaryLabelColor
        clearButton.refusesFirstResponder = true
        clearButton.toolTip = "Clear shortcut"
        clearButton.target = self
        clearButton.action = #selector(clear)
        addSubview(clearButton)

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: Self.size.height) }

    // MARK: - Drawing

    private func refresh() {
        let display = display
        switch display {
        case .empty:
            label.stringValue = RecorderDisplay.emptyTitle
            label.textColor = .secondaryLabelColor
        case .recording:
            label.stringValue = RecorderDisplay.recordingTitle
            label.textColor = .secondaryLabelColor
        case .set(let combo):
            label.stringValue = combo.displayString(characterKeyName: KeyNames.character(for: combo.carbonKeyCode))
            label.textColor = .labelColor
        }
        clearButton.isHidden = !display.showsClearButton
        setAccessibilityValue(label.stringValue)
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let buttonSide: CGFloat = 16
        let inset: CGFloat = 6
        clearButton.frame = NSRect(x: bounds.maxX - inset + 2 - buttonSide, y: bounds.midY - buttonSide / 2, width: buttonSide, height: buttonSide)
        let trailing = clearButton.isHidden ? inset : inset + buttonSide
        let height = label.intrinsicContentSize.height
        // Keep the text centered in the whole field; only shrink it away from the button.
        let width = bounds.width - 2 * max(inset, trailing)
        label.frame = NSRect(x: (bounds.width - width) / 2, y: bounds.midY - height / 2, width: width, height: height)
    }

    private var shape: NSBezierPath {
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        shape.fill()
        NSColor.separatorColor.setStroke()
        shape.lineWidth = 1
        shape.stroke()
    }

    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius).fill()
    }

    // MARK: - Focus

    override var acceptsFirstResponder: Bool { true }
    /// Tab reaches the recorder even with keyboard navigation off, like a text field.
    override var canBecomeKeyView: Bool { !isHiddenOrHasHiddenAncestor }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        let cause = focusCause()
        Log.recorder.notice("Recorder focused (\(String(describing: cause), privacy: .public))")
        if cause.startsRecording {
            startRecording()
        } else {
            // E.g. AppKit picking the recorder as the window's first key view: focus without
            // recording would look like recording, so give it back.
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isRecording else { return }
                self.resignFocus()
            }
        }
        return true
    }

    override func resignFirstResponder() -> Bool {
        guard super.resignFirstResponder() else { return false }
        stopRecording(reason: "recorder lost focus")
        return true
    }

    /// Clicks on the label land on the recorder; only the clear button handles its own.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit === clearButton ? hit : self
    }

    /// Only reached when focused but not recording; recording keys go to the event tap.
    override func keyDown(with event: NSEvent) {
        if Int(event.keyCode) == KeyCombo.tabKeyCode {
            moveFocus(backward: event.modifierFlags.contains(.shift))
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if window?.firstResponder === self {
            if !isRecording { startRecording() }
        } else {
            window?.makeFirstResponder(self)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        if window?.firstResponder !== self { window?.makeFirstResponder(self) }
        if !isRecording { startRecording() }
        return true
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        windowObserver = nil
        if newWindow == nil { stopRecording(reason: "recorder left its window") }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        // Window resigns key (another window or app, or Settings closed): give up focus.
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.resignFocus() }
        }
    }

    private func focusCause() -> RecorderFocusCause {
        if Self.isTabbingFromRecorder { return .tabFromRecorder }
        guard let event = NSApp.currentEvent, let window, event.window === window else { return .other }
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            let point = convert(event.locationInWindow, from: nil)
            return .mouseDown(insideRecorder: bounds.contains(point))
        case .keyDown:
            return .keyDown(keyCode: Int(event.keyCode))
        default:
            return .other
        }
    }

    private func resignFocus() {
        guard let window, window.firstResponder === self else { return }
        window.makeFirstResponder(nil)
    }

    // MARK: - Recording

    private func startRecording() {
        let started = ShortcutRecording.shared.start(id: recorderID, callbacks: .init(
            onResult: { [weak self] combo in
                self?.combo = combo
                self?.onChange?(combo)
            },
            onMoveFocus: { [weak self] backward in self?.moveFocus(backward: backward) },
            onEnd: { [weak self] in self?.recordingEnded() }
        ))
        isRecording = started
        // Couldn't record (Accessibility): don't sit focused looking like it records.
        if !started { DispatchQueue.main.async { [weak self] in self?.resignFocus() } }
    }

    func stopRecording(reason: String) {
        guard isRecording else { return }
        ShortcutRecording.shared.stop(reason: reason)
        isRecording = false
    }

    /// Recording ended on its own (captured, Esc, Delete, Tab, another recorder, app inactive).
    private func recordingEnded() {
        isRecording = false
        // Focus and recording go together; drop focus unless Tab already moved it. Deferred
        // because this may run inside resignFirstResponder.
        DispatchQueue.main.async { [weak self] in self?.resignFocus() }
    }

    private func moveFocus(backward: Bool) {
        guard let window else { return }
        Self.isTabbingFromRecorder = true
        defer { Self.isTabbingFromRecorder = false }
        if backward {
            window.selectKeyView(preceding: self)
        } else {
            window.selectKeyView(following: self)
        }
    }

    @objc private func clear() {
        combo = nil
        onChange?(nil)
    }
}
