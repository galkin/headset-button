import AppKit
import HeadsetButtonCore
import Observation
import ServiceManagement

/// Owns the app state, persists it and keeps the Now Playing slot in line with it.
@MainActor
@Observable
final class AppModel {
    private let store = BindingStore()
    @ObservationIgnored private var session: NowPlayingSession!
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var micMonitor: HeadsetMicMonitor!
    @ObservationIgnored private var connectionMonitor: HeadsetConnectionMonitor!
    @ObservationIgnored private var lastSlotReason: String?
    /// False until the Bindings and the connected Headsets are both read, so the first slot
    /// decision (and its log line) is not made on half the facts.
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var micNotificationRule = MicBusyNotificationRule()
    @ObservationIgnored private var highlightTask: Task<Void, Never>?

    var bindings: BindingSet {
        didSet {
            guard bindings != oldValue else { return }
            store.saveBindings(bindings)
            requestAccessibilityOnFirstShortcutBinding()
            refreshRows()
        }
    }

    var isEnabled: Bool {
        didSet {
            store.isEnabled = isEnabled
            apply()
        }
    }

    private(set) var isAccessibilityTrusted = Accessibility.isTrusted
    private(set) var playerActivity = PlayerActivity()
    private(set) var launchesAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var headsetMicBusy: HeadsetMicBusy?
    /// The connected Headsets: Bluetooth audio devices with output, default output or not.
    private(set) var headsets: [Headset] = []

    /// The Gestures table: each row's URL check and State. Recomputed when the Bindings or
    /// Accessibility change, and when the app becomes active (an app that opens a scheme may
    /// have been installed or removed meanwhile).
    private(set) var rows: [GestureRow] = []

    /// The last Gesture that arrived, for the Settings footer.
    private(set) var lastPress: (gesture: Gesture, date: Date)?
    /// The row that highlights briefly after its Gesture arrived.
    private(set) var highlightedGesture: Gesture?

    var state: ListenerState {
        ListenerState(
            isEnabled: isEnabled,
            bindings: rows.compactMap(\.binding),
            isAccessibilityTrusted: isAccessibilityTrusted,
            playingPlayer: playerActivity.playingPlayerName,
            headsetMicBusy: headsetMicBusy,
            headsets: headsets
        )
    }

    var status: ListenerStatus { state.status }

    init() {
        bindings = store.loadBindings()
        isEnabled = store.isEnabled
        session = NowPlayingSession { [weak self] gesture in self?.handle(gesture) }
        micMonitor = HeadsetMicMonitor { [weak self] busy in self?.headsetMicChanged(busy) }
        #if DEBUG
        // Debug only: any output counts as a Headset when none is connected, to test the slot without one.
        let fakeHeadset = ProcessInfo.processInfo.environment["HEADSET_BUTTON_FAKE_HEADSET"] == "1"
        #else
        let fakeHeadset = false
        #endif
        connectionMonitor = HeadsetConnectionMonitor(anyOutputCounts: fakeHeadset) { [weak self] headsets in
            self?.headsetsChanged(headsets)
        }
        observePlayers()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        refreshRows()
        connectionMonitor.start()
        micMonitor.start()
        isStarted = true
        apply()
    }

    // MARK: - Gestures

    private func handle(_ gesture: Gesture) {
        showPress(gesture)
        guard state.holdsSlot, let binding = rows.first(where: { $0.gesture == gesture })?.binding else {
            Log.action.notice("No Binding for \(gesture.rawValue, privacy: .public) gesture")
            return
        }
        run(binding.action)
    }

    /// The Settings row's Run button: fires the row's Action without the Headset.
    func runRow(_ gesture: Gesture) {
        guard let action = rows.first(where: { $0.gesture == gesture })?.runnableAction else { return }
        Log.action.notice("Run button for \(gesture.rawValue, privacy: .public) gesture")
        run(action)
    }

    private func run(_ action: Action) {
        micNotificationRule.actionRan(at: .now)
        ActionRunner.run(action)
    }

    private func showPress(_ gesture: Gesture) {
        lastPress = (gesture, .now)
        highlightedGesture = gesture
        highlightTask?.cancel()
        highlightTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.highlightedGesture = nil
        }
    }

    // MARK: - Rows

    func refreshRows() {
        let new = bindings.rows(isAccessibilityTrusted: isAccessibilityTrusted, lookup: ActionRunner.handler(for:))
        if new != rows { rows = new }
        apply()
    }

    // MARK: - Headset mic busy

    private func headsetMicChanged(_ busy: HeadsetMicBusy?) {
        headsetMicBusy = busy
        guard micNotificationRule.micBusyChanged(busy != nil, at: .now), let busy else { return }
        // The recording app's process may name itself a moment after the device starts.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            Notifications.postHeadsetMicBusy(self?.headsetMicBusy ?? busy)
        }
    }

    // MARK: - Headset

    private func headsetsChanged(_ new: [Headset]) {
        guard new != headsets else { return }
        headsets = new
        apply()
    }

    private func apply() {
        guard isStarted else { return }
        let state = self.state
        if state.slotReason != lastSlotReason {
            lastSlotReason = state.slotReason
            Log.slot.notice("Slot \(state.slotReason, privacy: .public)")
        }
        session.update(hold: state.holdsSlot, yieldToPlayer: state.yieldsToPlayer)
    }

    private func tick() {
        refreshAccessibility()
        session.heartbeat()
    }

    // MARK: - Accessibility

    func refreshAccessibility() {
        let trusted = Accessibility.isTrusted
        guard trusted != isAccessibilityTrusted else { return }
        isAccessibilityTrusted = trusted
        refreshRows()
    }

    /// Accessibility is requested the first time a Press shortcut Binding is saved.
    private func requestAccessibilityOnFirstShortcutBinding() {
        guard bindings.hasPressShortcutBinding, !store.accessibilityRequested else { return }
        store.accessibilityRequested = true
        if !Accessibility.isTrusted { Accessibility.request() }
    }

    // MARK: - Launch at login

    func setLaunchesAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.action.error("Launch at login \(on ? "register" : "unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    func refreshLaunchAtLogin() {
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Media players

    private func observePlayers() {
        let distributed = DistributedNotificationCenter.default()
        for player in PlayerActivity.players {
            observers.append(distributed.addObserver(
                forName: Notification.Name(player.notificationName), object: nil, queue: .main
            ) { [weak self] note in
                let name = note.name.rawValue
                let playerState = note.userInfo?[PlayerActivity.playerStateKey] as? String
                MainActor.assumeIsolated { self?.playerChanged(notification: name, playerState: playerState) }
            })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let bundleID = app?.bundleIdentifier else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                var activity = self.playerActivity
                activity.playerQuit(bundleID: bundleID)
                self.setPlayerActivity(activity)
            }
        })
    }

    private func playerChanged(notification: String, playerState: String?) {
        var activity = playerActivity
        activity.record(notification: notification, playerState: playerState)
        Log.slot.notice("\(notification, privacy: .public): \(playerState ?? "no state", privacy: .public)")
        setPlayerActivity(activity)
    }

    private func setPlayerActivity(_ activity: PlayerActivity) {
        guard activity != playerActivity else { return }
        playerActivity = activity
        apply()
    }
}
