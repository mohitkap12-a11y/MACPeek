#if os(macOS)
import os

/// Local-only logging via the unified log. Nothing leaves the machine.
/// One category per utility (`MacPeek.<Name>`); never log secrets, clipboard contents or device serials.
enum Log {
    private static let subsystem = "app.macpeek.MacPeek"
    static let app = Logger(subsystem: subsystem, category: "MacPeek")
    static let portPeek = Logger(subsystem: subsystem, category: "MacPeek.PortPeek")
    static let fileLockPeek = Logger(subsystem: subsystem, category: "MacPeek.FileLockPeek")
    static let displayPeek = Logger(subsystem: subsystem, category: "MacPeek.DisplayPeek")
    static let usbPeek = Logger(subsystem: subsystem, category: "MacPeek.USBPeek")
    static let sleepPeek = Logger(subsystem: subsystem, category: "MacPeek.SleepPeek")
}
#endif
