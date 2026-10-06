#if os(macOS)
import Foundation
import UserNotifications

/// Posts "Port N freed" after a successful kill. Never used for refresh activity.
@MainActor
final class NotificationService {
    func notifyFreed(_ port: Int, processName: String, pid: Int) {
        // UNUserNotificationCenter requires a real app bundle (not `swift run`).
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Port \(port) freed"
        content.body = "\(processName) (PID \(pid)) was terminated."
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
