#if os(macOS)
import Foundation
@preconcurrency import UserNotifications
import VitalsKit

/// Posts alerts as macOS notifications and handles their buttons: **Show** opens MacPeek on the alert, **Don't Alert
/// About This App** adds the process to the ignore list. MacPeek is a menu-bar app, which macOS treats as always in the
/// foreground, so the delegate asks for banners to be shown anyway.
@MainActor
final class AlertNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let category = "app.macpeek.alert"
    static let processCategory = "app.macpeek.alert.process"
    static let ignoreAction = "app.macpeek.alert.ignore"

    /// Opens MacPeek on the alerts screen.
    var onShow: (() -> Void)?
    var onIgnore: ((String) -> Void)?
    private var installed = false

    /// UNUserNotificationCenter requires a real app bundle (not `swift run`).
    private var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    func install() {
        guard isAvailable, !installed else { return }
        installed = true
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let ignore = UNNotificationAction(identifier: Self.ignoreAction, title: "Don't Alert About This App", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.processCategory, actions: [ignore], intentIdentifiers: []),
        ])
    }

    func post(_ event: AlertEvent) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.message
        content.categoryIdentifier = event.processName == nil ? Self.category : Self.processCategory
        if let name = event.processName { content.userInfo = ["process": name] }
        content.threadIdentifier = event.kind.rawValue
        if event.isCritical { content.interruptionLevel = .timeSensitive }
        let request = UNNotificationRequest(identifier: event.id.uuidString, content: content, trigger: nil)
        let center = UNUserNotificationCenter.current()
        // Add the request only once authorization is known: adding it while the prompt is pending would drop it.
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                center.add(request)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { center.add(request) }
                }
            default:
                break
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let category = response.notification.request.content.categoryIdentifier
        let process = response.notification.request.content.userInfo["process"] as? String
        Task { @MainActor in
            if action == Self.ignoreAction, let process {
                self.onIgnore?(process)
            } else if action == UNNotificationDefaultActionIdentifier,
                      category == Self.category || category == Self.processCategory {
                self.onShow?()
            }
        }
        completionHandler()
    }
}
#endif
