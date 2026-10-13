#if os(macOS)
import Foundation
@preconcurrency import UserNotifications

/// Posts a notification after a successful kill ("Port 3000 freed"). Never used for refresh activity.
@MainActor
final class NotificationService {
    func notifyFreed(_ port: Int, processName: String, pid: Int) {
        notify(title: "Port \(port) freed", body: "\(processName) (PID \(pid)) was terminated.")
    }

    func notify(title: String, body: String) {
        // UNUserNotificationCenter requires a real app bundle (not `swift run`).
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)

        // Only add the request once authorization is known: adding it while the permission
        // prompt is still pending would silently drop the very first notification.
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                center.add(request)
            case .notDetermined:
                center.requestAuthorization(options: [.alert]) { granted, _ in
                    if granted { center.add(request) }
                }
            default:
                break
            }
        }
    }
}
#endif
