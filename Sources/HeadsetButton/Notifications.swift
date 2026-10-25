import HeadsetButtonCore
import UserNotifications

/// Posts the Headset mic busy notification. Authorization is requested lazily, the first
/// time a notification is needed.
@MainActor
enum Notifications {
    static func postHeadsetMicBusy(_ busy: HeadsetMicBusy) {
        let body = MicBusyNotificationRule.body(for: busy)
        Task {
            let center = UNUserNotificationCenter.current()
            do {
                guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                    Log.mic.error("Notification not posted (not authorized): \(body, privacy: .public)")
                    return
                }
                let content = UNMutableNotificationContent()
                content.title = "Headset mic in use"
                content.body = body
                try await center.add(UNNotificationRequest(identifier: "headset-mic-busy", content: content, trigger: nil))
                Log.mic.notice("Notified: \(body, privacy: .public)")
            } catch {
                Log.mic.error("Notification failed: \(error.localizedDescription, privacy: .public): \(body, privacy: .public)")
            }
        }
    }
}
