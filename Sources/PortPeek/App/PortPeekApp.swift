#if os(macOS)
import AppKit

@main
enum PortPeekApp {
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
enum PortPeekApp {
    static func main() { print("PortPeek is a macOS menu-bar app. Run `swift test` to exercise the core.") }
}
#endif
