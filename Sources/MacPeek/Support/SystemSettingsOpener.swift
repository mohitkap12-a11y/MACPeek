#if os(macOS)
import AppKit
import MacPeekCore

/// Opens a System Settings pane. Tries the pane's URLs from most to least specific and stops at the first that macOS
/// accepts, so a deep link that a macOS version no longer honours falls back to a broader pane instead of doing nothing.
enum SystemSettingsOpener {
    @discardableResult
    static func open(_ pane: SystemSettingsPane) -> Bool {
        for url in pane.candidateURLs where NSWorkspace.shared.open(url) { return true }
        return false
    }
}
#endif
