import Foundation

/// One resolver block of `scutil --dns`.
public struct DNSResolver: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// The resolver used for ordinary names: no domain of its own, with name servers.
        case standard
        /// Only for names under `domain`.
        case domainSpecific
        /// Multicast DNS (`.local` and the link-local reverse zones). Answered on the local network, not by a server.
        case multicast
    }

    public let id: String
    public let number: Int
    public let nameservers: [String]
    public let domain: String?
    public let searchDomains: [String]
    /// e.g. "en1".
    public let interface: String?
    public let options: String?
    public let timeoutSeconds: Int?
    public let flags: [String]
    /// macOS's own words: "Reachable", "Not Reachable"… nil when the block has no reach line.
    public let reachability: String?
    public let order: Int?
    public let isScoped: Bool

    public init(id: String, number: Int, nameservers: [String], domain: String?, searchDomains: [String], interface: String?,
                options: String?, timeoutSeconds: Int?, flags: [String], reachability: String?, order: Int?, isScoped: Bool) {
        self.id = id
        self.number = number
        self.nameservers = nameservers
        self.domain = domain
        self.searchDomains = searchDomains
        self.interface = interface
        self.options = options
        self.timeoutSeconds = timeoutSeconds
        self.flags = flags
        self.reachability = reachability
        self.order = order
        self.isScoped = isScoped
    }

    public var kind: Kind {
        if options?.lowercased().contains("mdns") == true { return .multicast }
        return domain == nil ? .standard : .domainSpecific
    }

    public var isReachable: Bool? { reachability.map { !$0.lowercased().contains("not") } }
}

public struct DNSConfiguration: Equatable, Sendable {
    public let resolvers: [DNSResolver]
    public let scopedResolvers: [DNSResolver]

    public init(resolvers: [DNSResolver], scopedResolvers: [DNSResolver]) {
        self.resolvers = resolvers
        self.scopedResolvers = scopedResolvers
    }

    /// The resolver macOS uses for ordinary names: the first standard one that has name servers.
    public var primary: DNSResolver? { resolvers.first { $0.kind == .standard && !$0.nameservers.isEmpty } }

    /// The name servers asked for ordinary lookups, in order.
    public var activeServers: [String] { primary?.nameservers ?? [] }

    public var searchDomains: [String] { resolvers.flatMap(\.searchDomains).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } } }
    public var domainResolvers: [DNSResolver] { resolvers.filter { $0.kind == .domainSpecific } }
    public var multicastResolvers: [DNSResolver] { resolvers.filter { $0.kind == .multicast } }

    /// Plain text for a support thread.
    public var copyText: String {
        var lines = ["DNS servers in use: " + (activeServers.isEmpty ? "none" : activeServers.joined(separator: ", "))]
        if let interface = primary?.interface { lines.append("Interface: \(interface)") }
        if !searchDomains.isEmpty { lines.append("Search domains: " + searchDomains.joined(separator: ", ")) }
        for resolver in domainResolvers { lines.append("\(resolver.domain ?? ""): " + resolver.nameservers.joined(separator: ", ")) }
        return lines.joined(separator: "\n")
    }
}

/// The outcome of asking one DNS server directly.
public struct ServerProbe: Identifiable, Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        /// The server answered; `status` is the DNS response code (NOERROR, NXDOMAIN…).
        case answered(queryMilliseconds: Int?, status: String, answers: Int)
        case timedOut
        case unavailable(String)
    }

    public var id: String { server }
    public let server: String
    public let outcome: Outcome

    public init(server: String, outcome: Outcome) {
        self.server = server
        self.outcome = outcome
    }
}

/// The outcome of a lookup through the Mac's own resolver (what apps actually use).
public struct SystemLookup: Equatable, Sendable {
    public let name: String
    public let addresses: [String]
    /// Wall-clock time of the whole `dscacheutil` run. It includes starting the tool, and the answer may come
    /// from a cache, so it is an approximation rather than the resolver's own timing.
    public let elapsedMilliseconds: Int

    public init(name: String, addresses: [String], elapsedMilliseconds: Int) {
        self.name = name
        self.addresses = addresses
        self.elapsedMilliseconds = elapsedMilliseconds
    }
}
