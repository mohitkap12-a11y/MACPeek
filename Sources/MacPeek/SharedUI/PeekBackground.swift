#if os(macOS)
import SwiftUI
import AppKit

extension Color {
    /// Popover background. Dark mode keeps the system window colour; light mode uses a soft grey
    /// instead of the system's bright white, which is harsh in a small menu-bar popover.
    static let peekBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .windowBackgroundColor
            : NSColor(srgbRed: 0.918, green: 0.922, blue: 0.937, alpha: 1)
    })
}
#endif
