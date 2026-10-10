import Foundation

/// A System Settings destination, described as an ordered list of URLs to try: the most specific route first, then
/// progressively more general fallbacks, ending at System Settings itself. Pure data, so the routes are testable
/// anywhere; the app layer opens them with `NSWorkspace`. Deep links are an Apple convention, not a documented API, so a
/// route that does not resolve on some macOS version must degrade to the next one rather than fail.
public struct SystemSettingsPane: Equatable, Sendable {
    public let id: String
    public let title: String
    public let urlStrings: [String]

    public init(id: String, title: String, urlStrings: [String]) {
        self.id = id
        self.title = title
        self.urlStrings = urlStrings
    }

    public static let scheme = "x-apple.systempreferences"
    /// Opens System Settings at wherever it was last left.
    public static let rootURLString = "x-apple.systempreferences:"

    public var candidateURLs: [URL] { urlStrings.compactMap { URL(string: $0) } }

    public static let sound = SystemSettingsPane(
        id: "sound", title: "Sound",
        urlStrings: ["x-apple.systempreferences:com.apple.Sound-Settings.extension", rootURLString])
    public static let softwareUpdate = SystemSettingsPane(
        id: "softwareUpdate", title: "Software Update",
        urlStrings: ["x-apple.systempreferences:com.apple.Software-Update-Settings.extension",
                     "x-apple.systempreferences:com.apple.preferences.softwareupdate", rootURLString])
}
