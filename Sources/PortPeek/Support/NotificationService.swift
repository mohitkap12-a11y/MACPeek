#if os(macOS)
import Foundation
import UserNotifications

/// Posts "Port N freed" after a successful kill. Never used for refresh activity.
@MainActor
final class NotificationService {
    private var authorizationRequested = false

    func notifyFreed(_ port: Int, processName: String, pid: Int) {
        // UNUserNotificationCenter requires a real app bundle (not `swift run`).
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        if !authorizationRequested {
            authorizationRequested = true
            center.requestAuthorization(options: [.alert]) { _, _ in }
        }
        let content = UNMutableNotificationContent()
        content.title = "Port \(port) freed"
        content.body = "\(processName) (PID \(pid)) was terminated."
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
#endif
