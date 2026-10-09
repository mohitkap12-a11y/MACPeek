import Foundation
import MacPeekCore

/// One macOS privacy permission category, described in plain language. This is static, hand-written reference content:
/// PrivacyPeek never reads which apps hold a permission and never changes one.
public struct PrivacyCategory: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    /// One line shown in the list.
    public let summary: String
    /// What granting it generally allows an app to do.
    public let whatItAllows: String
    /// Extra context, e.g. an on-screen indicator or how the category changed between macOS versions.
    public let note: String?
    public let symbol: String
    public let pane: SystemSettingsPane

    public init(id: String, name: String, summary: String, whatItAllows: String, note: String? = nil,
                symbol: String, pane: SystemSettingsPane) {
        self.id = id
        self.name = name
        self.summary = summary
        self.whatItAllows = whatItAllows
        self.note = note
        self.symbol = symbol
        self.pane = pane
    }

    /// Everything the Learn disclosure and a copy action show.
    public var copyText: String {
        ([name, whatItAllows] + [note].compactMap { $0 }).joined(separator: "\n")
    }
}

public enum PrivacyCatalog {
    /// What PrivacyPeek does not do, shown on screen and checked by tests.
    public static let disclaimer =
        "PrivacyPeek explains what each permission means and opens the right System Settings pane. It does not read which apps have a permission, and it cannot grant, revoke or reset one. macOS decides every authorization."
    public static let notAVerdict =
        "A permission being granted does not mean an app is unsafe, and one being absent does not mean it is safe."
    public static let openFailed =
        "System Settings could not be opened to that pane. Open System Settings and choose Privacy & Security."

    /// Categories that exist on the given macOS major version, in display order.
    /// - Note: Names and availability reflect Apple's documentation and each pane's behaviour as observed by the
    ///   maintainers; they were not machine-verified on every macOS version (see docs/utilities/privacypeek.md).
    public static func categories(forMajorVersion major: Int) -> [PrivacyCategory] {
        var result: [PrivacyCategory] = [
            PrivacyCategory(
                id: "camera", name: "Camera",
                summary: "Use the built-in or a connected camera.",
                whatItAllows: "Lets an app capture photos and video from your cameras.",
                note: "macOS shows a green indicator in the menu bar while a camera is in use.",
                symbol: "camera", pane: .privacy(id: "camera", title: "Camera", anchor: "Privacy_Camera")),
            PrivacyCategory(
                id: "microphone", name: "Microphone",
                summary: "Record audio from microphones.",
                whatItAllows: "Lets an app record sound from the built-in or a connected microphone.",
                note: "macOS shows an orange indicator in the menu bar while a microphone is in use.",
                symbol: "mic", pane: .privacy(id: "microphone", title: "Microphone", anchor: "Privacy_Microphone")),
            PrivacyCategory(
                id: "screen", name: major >= 15 ? "Screen & System Audio Recording" : "Screen Recording",
                summary: major >= 15 ? "Capture the contents of your screen and system audio." : "Capture the contents of your screen.",
                whatItAllows: major >= 15
                    ? "Lets an app record or stream what is shown on your screen, including other apps' windows, and the sound your Mac plays."
                    : "Lets an app record or stream what is shown on your screen, including other apps' windows.",
                note: major >= 15 ? "Before macOS 15 this category was named Screen Recording." : nil,
                symbol: "rectangle.dashed.badge.record",
                pane: .privacy(id: "screen", title: "Screen Recording", anchor: "Privacy_ScreenCapture")),
            PrivacyCategory(
                id: "accessibility", name: "Accessibility",
                summary: "Control this Mac and other apps.",
                whatItAllows: "Lets an app read and operate other apps' interface elements and send clicks and keystrokes. It is a powerful permission, intended for assistive technology and automation tools.",
                symbol: "accessibility", pane: .privacy(id: "accessibility", title: "Accessibility", anchor: "Privacy_Accessibility")),
            PrivacyCategory(
                id: "inputMonitoring", name: "Input Monitoring",
                summary: "Observe keyboard, mouse and trackpad input.",
                whatItAllows: "Lets an app receive keystrokes and pointer input even while you are using another app.",
                symbol: "keyboard", pane: .privacy(id: "inputMonitoring", title: "Input Monitoring", anchor: "Privacy_ListenEvent")),
            PrivacyCategory(
                id: "fullDiskAccess", name: "Full Disk Access",
                summary: "Read data macOS normally protects.",
                whatItAllows: "Lets an app read areas other apps' data is kept in, such as Mail, Messages, Safari data and Time Machine backups, without a separate prompt for each.",
                symbol: "externaldrive", pane: .privacy(id: "fullDiskAccess", title: "Full Disk Access", anchor: "Privacy_AllFiles")),
            PrivacyCategory(
                id: "filesAndFolders", name: "Files & Folders",
                summary: "Reach specific folders.",
                whatItAllows: "Lets an app open files in protected folders such as Desktop, Documents and Downloads, in iCloud Drive, and on removable or network volumes. macOS asks per folder.",
                symbol: "folder", pane: .privacy(id: "filesAndFolders", title: "Files & Folders", anchor: "Privacy_FilesAndFolders")),
            PrivacyCategory(
                id: "location", name: "Location Services",
                summary: "Know roughly where this Mac is.",
                whatItAllows: "Lets an app use your Mac's location, estimated from nearby Wi-Fi networks and other signals.",
                note: "macOS also hides Wi-Fi network names from apps that do not have Location access.",
                symbol: "location", pane: .privacy(id: "location", title: "Location Services", anchor: "Privacy_LocationServices")),
            PrivacyCategory(
                id: "contacts", name: "Contacts",
                summary: "Read your contacts.",
                whatItAllows: "Lets an app read, and with some permissions change, the people stored in Contacts.",
                symbol: "person.crop.circle", pane: .privacy(id: "contacts", title: "Contacts", anchor: "Privacy_Contacts")),
            PrivacyCategory(
                id: "calendars", name: "Calendars",
                summary: "Read your calendar events.",
                whatItAllows: "Lets an app read, and with some permissions change, your calendar events.",
                symbol: "calendar", pane: .privacy(id: "calendars", title: "Calendars", anchor: "Privacy_Calendars")),
            PrivacyCategory(
                id: "photos", name: "Photos",
                summary: "Read your photo library.",
                whatItAllows: "Lets an app view your Photos library, and with some permissions add to or change it.",
                symbol: "photo", pane: .privacy(id: "photos", title: "Photos", anchor: "Privacy_Photos")),
            PrivacyCategory(
                id: "bluetooth", name: "Bluetooth",
                summary: "Find and talk to Bluetooth devices.",
                whatItAllows: "Lets an app discover and connect to nearby Bluetooth devices.",
                symbol: "wave.3.right", pane: .privacy(id: "bluetooth", title: "Bluetooth", anchor: "Privacy_Bluetooth")),
        ]
        if major >= 15 {
            result.append(PrivacyCategory(
                id: "localNetwork", name: "Local Network",
                summary: "Reach devices on your local network.",
                whatItAllows: "Lets an app find and connect to other devices on your home or office network, such as printers, speakers and computers.",
                symbol: "network", pane: .privacy(id: "localNetwork", title: "Local Network", anchor: "Privacy_LocalNetwork")))
        }
        return result
    }
}
