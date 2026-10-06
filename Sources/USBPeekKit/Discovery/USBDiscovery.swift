import Foundation
import MacPeekCore

public enum USBError: Error, Equatable, LocalizedError {
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let detail): return detail
        }
    }
}

public protocol USBDiscovering: Sendable {
    func snapshot() async throws -> USBSnapshot
}

/// Reads connected USB devices from the I/O registry (`ioreg -p IOUSB -l -w0`) and Thunderbolt/USB4 ports
/// from `system_profiler SPThunderboltDataType -json`. Both are read-only and need no permissions.
///
/// USB comes from ioreg rather than `system_profiler SPUSBDataType` because the latter was observed returning an
/// empty list on a Mac that had USB devices attached. A Thunderbolt failure never hides the USB results.
public struct SystemUSBDiscovery: USBDiscovering {
    static let ioreg = "/usr/sbin/ioreg"
    static let ioregArguments = ["-p", "IOUSB", "-l", "-w0"]
    static let profiler = "/usr/sbin/system_profiler"
    static let thunderboltArguments = ["SPThunderboltDataType", "-json"]
    private let runner: CommandRunning

    public init(runner: CommandRunning = ShellCommand(timeout: 20)) {
        self.runner = runner
    }

    public func snapshot() async throws -> USBSnapshot {
        let usb = try await runner.run(Self.ioreg, Self.ioregArguments)
        guard usb.status == 0 else {
            let detail = usb.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw USBError.commandFailed(detail.isEmpty ? "ioreg exited with status \(usb.status)" : detail)
        }
        let buses = IORegUSBParser.parse(usb.stdout)

        var ports: [ThunderboltPort] = []
        var note: String?
        do {
            try Task.checkCancellation()
            let output = try await runner.run(Self.profiler, Self.thunderboltArguments)
            if output.status == 0, let parsed = ThunderboltParser.parse(output.stdout) {
                ports = parsed
            } else {
                note = "Thunderbolt information is not available on this Mac."
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch CommandError.cancelled {
            throw CommandError.cancelled
        } catch {
            note = "Thunderbolt information could not be read."
        }
        return USBSnapshot(buses: buses, thunderboltPorts: ports, thunderboltNote: note)
    }
}
