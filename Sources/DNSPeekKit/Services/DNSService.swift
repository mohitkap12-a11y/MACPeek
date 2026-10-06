import Foundation
import MacPeekCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum DNSError: Error, Equatable, LocalizedError {
    case commandFailed(String)
    case invalidName
    case invalidServer

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let detail): return detail
        case .invalidName: return "Enter a valid domain name, such as apple.com."
        case .invalidServer: return "That is not an IP address MacPeek can query."
        }
    }
}

/// Values handed to external tools are validated first, so nothing the user types (or a resolver config contains)
/// can become an option or an extra argument.
public enum NetworkInput {
    private static let hostname = NSRegularExpression.compile(
        #"^(?=.{1,253}$)([A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?\.)*[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?\.?$"#)

    public static func isHostname(_ value: String) -> Bool { hostname.groups(in: value) != nil }

    public static func isIPv4(_ value: String) -> Bool {
        var address = in_addr()
        return value.withCString { inet_pton(AF_INET, $0, &address) } == 1
    }

    public static func isIPv6(_ value: String) -> Bool {
        // Zone ids (`fe80::1%en0`) are rejected on purpose: some libc versions accept
        // them, and nothing but a plain address should ever reach `dig`/`ping`.
        guard !value.contains("%") else { return false }
        var address = in6_addr()
        return value.withCString { inet_pton(AF_INET6, $0, &address) } == 1
    }

    public static func isIPAddress(_ value: String) -> Bool { isIPv4(value) || isIPv6(value) }
}

public protocol DNSReading: Sendable {
    func configuration() async throws -> DNSConfiguration
    func lookup(name: String) async throws -> SystemLookup
    func probe(server: String, name: String) async throws -> ServerProbe
}

/// Read-only: `scutil --dns` for the configuration; lookups only when the user asks. Never changes DNS settings.
public struct SystemDNSReader: DNSReading {
    static let scutil = "/usr/sbin/scutil"
    static let dscacheutil = "/usr/bin/dscacheutil"
    static let dig = "/usr/bin/dig"
    private let runner: CommandRunning

    public init(runner: CommandRunning = ShellCommand(timeout: 10)) {
        self.runner = runner
    }

    public func configuration() async throws -> DNSConfiguration {
        let output = try await runner.run(Self.scutil, ["--dns"])
        guard output.status == 0 else {
            let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw DNSError.commandFailed(detail.isEmpty ? "scutil exited with status \(output.status)" : detail)
        }
        return ScutilDNSParser.parse(output.stdout)
    }

    public func lookup(name: String) async throws -> SystemLookup {
        guard NetworkInput.isHostname(name) else { throw DNSError.invalidName }
        let start = Date()
        let output = try await runner.run(Self.dscacheutil, ["-q", "host", "-a", "name", name])
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)
        guard output.status == 0 else {
            let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw DNSError.commandFailed(detail.isEmpty ? "dscacheutil exited with status \(output.status)" : detail)
        }
        return SystemLookup(name: name, addresses: DSCacheUtilParser.addresses(output.stdout), elapsedMilliseconds: elapsed)
    }

    public func probe(server: String, name: String) async throws -> ServerProbe {
        guard NetworkInput.isHostname(name) else { throw DNSError.invalidName }
        guard NetworkInput.isIPAddress(server) else { throw DNSError.invalidServer }
        let output = try await runner.run(Self.dig, ["@" + server, name, "A", "+time=2", "+tries=1"])
        return ServerProbe(server: server, outcome: DigParser.outcome(output: output.stdout + output.stderr, status: output.status))
    }
}
