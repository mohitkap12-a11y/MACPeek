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
    static let processPeek = Logger(subsystem: subsystem, category: "MacPeek.ProcessPeek")
    static let diskPeek = Logger(subsystem: subsystem, category: "MacPeek.DiskPeek")
    static let netPeek = Logger(subsystem: subsystem, category: "MacPeek.NetPeek")
    static let dnsPeek = Logger(subsystem: subsystem, category: "MacPeek.DNSPeek")
    // EnvPeek deliberately never logs variable names or values, only that a read failed.
    static let envPeek = Logger(subsystem: subsystem, category: "MacPeek.EnvPeek")
}
#endif
