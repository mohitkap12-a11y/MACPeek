import Foundation

/// Discovers listening sockets visible to the current user via `lsof`.
/// No elevated privileges are requested: sockets owned by other users are simply not listed.
public struct LsofPortDiscovery: PortDiscoveryProtocol {
    public static let arguments = [
        "-nP",                 // no DNS / port-name lookups (fast, numeric)
        "+c", "0",             // full command names
        "-iTCP", "-sTCP:LISTEN",
        "-iUDP",
        "-FpcLftPnT",          // machine-readable field output
    ]

    private let runner: CommandRunning
    private let lsofPath: String

    public init(runner: CommandRunning = ShellCommand(), lsofPath: String = "/usr/sbin/lsof") {
        self.runner = runner
        self.lsofPath = lsofPath
    }

    public func discover() async throws -> [PortInfo] {
        let output: CommandOutput
        do {
            output = try await runner.run(lsofPath, Self.arguments)
        } catch {
            throw PortDiscoveryError.commandFailed(error.localizedDescription)
        }
        // lsof exits 1 when a search selection matches nothing (e.g. no UDP sockets) — also when
        // others matched — so status 1 is only a failure when it produced no data and an error.
        // Status > 1 is always a failure, even with partial stdout, so a broken run can never
        // replace the last good list or be mistaken for "port released".
        let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if output.status > 1 || (output.status == 1 && output.stdout.isEmpty && !detail.isEmpty) {
            throw PortDiscoveryError.commandFailed(detail.isEmpty ? "lsof exited with status \(output.status)" : detail)
        }
        return PortParser.parse(output.stdout)
    }
}
