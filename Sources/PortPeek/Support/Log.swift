#if os(macOS)
import os

/// Local-only logging via the unified log. Nothing leaves the machine.
enum Log {
    static let app = Logger(subsystem: "app.portpeek.PortPeek", category: "app")
    static let scan = Logger(subsystem: "app.portpeek.PortPeek", category: "scan")
    static let kill = Logger(subsystem: "app.portpeek.PortPeek", category: "kill")
}
#endif
