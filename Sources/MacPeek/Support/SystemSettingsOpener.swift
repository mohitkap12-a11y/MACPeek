#if os(macOS)
import AppKit
import MacPeekCore

/// Opens a System Settings pane. Tries the pane's URLs in order and stops at the first that macOS accepts.
/// Limit: `NSWorkspace.open` reports whether the URL was handed to System Settings, not whether the pane exists, so a
/// pane identifier that a macOS version no longer honours is not detected and the fallbacks only help when the open
/// itself fails. Every route must therefore be checked by hand on each supported macOS version.
enum SystemSettingsOpener {
    @discardableResult
    static func open(_ pane: SystemSettingsPane) -> Bool {
        for url in pane.candidateURLs where NSWorkspace.shared.open(url) { return true }
        return false
    }
}
#endif
