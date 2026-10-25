import AppKit
import HeadsetButtonCore
import SwiftUI

/// One window, no tabs: overall status, the Gestures table, General, Permissions
/// (design/headset-button.pen, board "Settings v2"). Rows apply as soon as they are valid.
struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
            StatusLine(status: model.status)

            SettingsSection("Gestures") {
                GesturesTable(model: model)
            }

            SettingsSection("General") {
                Toggle(
                    isOn: SwiftUI.Binding(
                        get: { model.launchesAtLogin },
                        set: { model.setLaunchesAtLogin($0) }
                    )
                ) {
                    Text("Launch at login")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
                .padding(.horizontal, Layout.boxInset)
                .padding(.vertical, 12)
            }

            if model.bindings.hasPressShortcutKind {
                SettingsSection("Permissions") {
                    AccessibilityRow(isTrusted: model.isAccessibilityTrusted)
                }
            }
        }
        // Every section shares one content width (the Gestures table's) and one inset; the
        // window takes its size from the content (`.windowResizability(.contentSize)`).
        .frame(width: Layout.contentWidth)
        .padding(Layout.windowInset)
        .fixedSize()
        .onAppear {
            model.refreshAccessibility()
            model.refreshLaunchAtLogin()
            model.refreshRows()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshAccessibility()
            model.refreshRows()
        }
    }
}

// MARK: - Layout

/// One set of metrics for the whole window (design/settings-v2.png).
private enum Layout {
    /// From the window edge to every box.
    static let windowInset: CGFloat = 20
    /// From a box's edge to its content: status text, table columns, toggles.
    static let boxInset: CGFloat = 14
    /// From a box's edge to its section header.
    static let headerInset: CGFloat = 10
    static let sectionSpacing: CGFloat = 18
    static let cornerRadius: CGFloat = 8
    /// The width every box shares: the Gestures table plus its insets.
    static let contentWidth: CGFloat = Column.total + 2 * boxInset
}

// MARK: - Pieces

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .padding(.leading, Layout.headerInset)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quinary, in: RoundedRectangle(cornerRadius: Layout.cornerRadius))
        }
    }
}

private struct Dot: View {
    let color: Color
    var body: some View {
        Circle().fill(color).frame(width: 7, height: 7)
    }
}

private struct StatusLine: View {
    let status: ListenerStatus

    var body: some View {
        HStack(spacing: 8) {
            Dot(color: color)
            Text(status.detail).fontWeight(.medium)
        }
        .padding(.horizontal, Layout.boxInset)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: Layout.cornerRadius))
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch status {
        case .listening: .green
        case .accessibilityNeeded: .orange
        case .paused, .noHeadset, .headsetMicBusy, .playerHasHeadset: .gray
        }
    }
}

private struct AccessibilityRow: View {
    let isTrusted: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility")
                Text("Required to press keyboard shortcuts in other apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Dot(color: isTrusted ? .green : .orange)
                Text(isTrusted ? "Granted" : "Not granted").foregroundStyle(.secondary)
            }
            Button("Open System Settings…") { Accessibility.openSystemSettings() }
        }
        .padding(.horizontal, Layout.boxInset)
        .padding(.vertical, 12)
    }
}

// MARK: - Gestures table

/// Fixed column widths, shared by the header and every row so they line up. Every column,
/// "Run" included, is leading-aligned.
private enum Column {
    static let gesture: CGFloat = 96
    static let action: CGFloat = 150
    /// Fits a URL field for `superwhisper://record` and the 140 pt shortcut recorder.
    static let value: CGFloat = 220
    /// Fits "● Needs Accessibility".
    static let state: CGFloat = 146
    static let run: CGFloat = 44
    static let spacing: CGFloat = 12
    static let total: CGFloat = gesture + action + value + state + run + 4 * spacing
}

/// The hairline between the table's header and rows, inset like the row highlight.
private struct RowDivider: View {
    var body: some View {
        Divider().padding(.horizontal, 4)
    }
}

private struct GesturesTable: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ForEach(model.rows, id: \.gesture) { row in
                RowDivider()
                GestureRowView(
                    row: row,
                    draft: $model.bindings[row.gesture],
                    isHighlighted: model.highlightedGesture == row.gesture,
                    run: { model.runRow(row.gesture) }
                )
            }
            if let lastPress = model.lastPress {
                RowDivider()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Label(
                        LastPressText.text(
                            gesture: lastPress.gesture, elapsed: context.date.timeIntervalSince(lastPress.date)),
                        systemImage: "clock"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Layout.boxInset)
                .padding(.vertical, 8)
            }
        }
        .padding(.bottom, 4)
    }

    private var header: some View {
        HStack(spacing: Column.spacing) {
            Text("Gesture").frame(width: Column.gesture, alignment: .leading)
            Text("Action").frame(width: Column.action, alignment: .leading)
            Text("Value").frame(width: Column.value, alignment: .leading)
            Text("State").frame(width: Column.state, alignment: .leading)
            Text("Run").frame(width: Column.run, alignment: .leading)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Layout.boxInset)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }
}

private struct GestureRowView: View {
    let row: GestureRow
    @SwiftUI.Binding var draft: BindingDraft
    let isHighlighted: Bool
    let run: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Column.spacing) {
            Text(row.gesture.title)
                .fontWeight(isHighlighted ? .semibold : .regular)
                .frame(width: Column.gesture, alignment: .leading)

            Picker("Action for \(row.gesture.title)", selection: $draft.kind) {
                ForEach(ActionKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .labelsHidden()
            .frame(width: Column.action, alignment: .leading)

            value
                .frame(width: Column.value, alignment: .leading)

            stateLabel
                .frame(width: Column.state, alignment: .leading)

            Button("Run", action: run)
                .disabled(row.runnableAction == nil)
                .frame(width: Column.run, alignment: .leading)
        }
        .padding(.horizontal, Layout.boxInset)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.accentColor.opacity(isHighlighted ? 0.2 : 0))
                .padding(.horizontal, 4)
        )
        .animation(.easeOut(duration: 0.3), value: isHighlighted)
    }

    @ViewBuilder private var value: some View {
        switch draft.kind {
        case .none:
            Text("—").foregroundStyle(.secondary)
        case .openURL:
            URLField(gesture: row.gesture, text: $draft.urlText, validation: row.urlValidation)
        case .pressShortcut:
            ShortcutRecorderField(title: "Shortcut for \(row.gesture.title)", combo: $draft.shortcut)
        }
    }

    @ViewBuilder private var stateLabel: some View {
        if let title = row.state.title {
            HStack(spacing: 6) {
                Dot(color: stateColor)
                Text(title).foregroundStyle(row.state == .invalidURL ? Color.red : Color.primary)
            }
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }

    private var stateColor: Color {
        switch row.state {
        case .active: .green
        case .needsAccessibility: .orange
        case .invalidURL: .red
        case .incomplete, .none: .gray
        }
    }
}

private struct URLField: View {
    let gesture: Gesture
    @SwiftUI.Binding var text: String
    let validation: URLValidation

    private var isInvalid: Bool {
        switch validation {
        case .notAURL, .noApp: true
        case .empty, .opens: false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            TextField("URL for \(gesture.title)", text: $text, prompt: Text("superwhisper://record"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.red, lineWidth: isInvalid ? 1.5 : 0)
                )
            caption
                .font(.caption)
        }
    }

    @ViewBuilder private var caption: some View {
        switch validation {
        case .empty:
            EmptyView()
        case .opens(let handler):
            HStack(spacing: 4) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: handler.appPath))
                    .resizable()
                    .frame(width: 14, height: 14)
                Text(validation.caption ?? "")
            }
            .foregroundStyle(.secondary)
        case .notAURL, .noApp:
            Label(validation.caption ?? "", systemImage: "exclamationmark.circle")
                .foregroundStyle(.red)
        }
    }
}
