#if os(macOS)
import AppKit

@main
enum MacPeekApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let lifecycle = AppLifecycle()
        app.delegate = lifecycle
        app.setActivationPolicy(.accessory) // menu bar only: no Dock icon, no main window
        app.run()
        withExtendedLifetime(lifecycle) {}
    }
}
#else
@main
enum MacPeekApp {
    static func main() { print("MacPeek is a macOS menu-bar app. Run `swift test` to exercise the core libraries.") }
}
#endif
