import Foundation
import MacPeekCore

/// One mapping in `/etc/hosts`.
public struct HostsEntry: Identifiable, Equatable, Codable, Sendable {
    public var id: Int { line }
    public let address: String
    public let names: [String]
    /// The line number in the file, so the person can find it.
    public let line: Int
    /// The entries macOS ships with (localhost, broadcasthost): listed apart, as they are not overrides anyone added.
    public let isDefault: Bool

    public init(address: String, names: [String], line: Int, isDefault: Bool) {
        self.address = address
        self.names = names
        self.line = line
        self.isDefault = isDefault
    }
}

/// One file in `/etc/resolver/`: the file name is the domain, and its contents say which servers answer for it.
public struct ResolverFile: Identifiable, Equatable, Codable, Sendable {
    public var id: String { domain }
    public let domain: String
    public let nameservers: [String]
    public let port: Int?
    public let searchOrder: Int?
    /// Any other settings, as written (`timeout 5`, `options ndots:2`…).
    public let otherSettings: [String]

    public init(domain: String, nameservers: [String], port: Int?, searchOrder: Int?, otherSettings: [String]) {
        self.domain = domain
        self.nameservers = nameservers
        self.port = port
        self.searchOrder = searchOrder
        self.otherSettings = otherSettings
    }
}

/// Local overrides of name resolution: the usual answer to "why does this domain resolve to the wrong address?".
public struct DNSOverrides: Equatable, Codable, Sendable {
    public let hostsEntries: [HostsEntry]
    /// Set when `/etc/hosts` could not be read.
    public let hostsNote: String?
    public let resolverFiles: [ResolverFile]
    /// Set when `/etc/resolver` exists but could not be read.
    public let resolverNote: String?

    public init(hostsEntries: [HostsEntry], hostsNote: String?, resolverFiles: [ResolverFile], resolverNote: String?) {
        self.hostsEntries = hostsEntries
        self.hostsNote = hostsNote
        self.resolverFiles = resolverFiles
        self.resolverNote = resolverNote
    }

    public var customHostsEntries: [HostsEntry] { hostsEntries.filter { !$0.isDefault } }
    public var hasOverrides: Bool { !customHostsEntries.isEmpty || !resolverFiles.isEmpty }

    /// Which overrides apply to `name`, in plain words. `/etc/hosts` matches the exact name; a resolver file matches
    /// its domain and every name under it.
    public func explain(name raw: String) -> [String] {
        let name = Self.normalized(raw)
        guard !name.isEmpty else { return [] }
        var result: [String] = []
        for entry in hostsEntries where entry.names.contains(where: { Self.normalized($0) == name }) {
            result.append("/etc/hosts line \(entry.line) maps \(name) to \(entry.address). The system resolver uses this before asking any DNS server.")
        }
        for file in resolverFiles {
            let domain = Self.normalized(file.domain)
            if name == domain || name.hasSuffix("." + domain) {
                let servers = file.nameservers.isEmpty ? "no servers listed" : file.nameservers.joined(separator: ", ")
                result.append("/etc/resolver/\(file.domain) sends lookups for *.\(domain) to \(servers)\(file.port.map { " on port \($0)" } ?? "").")
            }
        }
        return result
    }

    static func normalized(_ name: String) -> String {
        var value = name.trimmingCharacters(in: .whitespaces).lowercased()
        while value.hasSuffix(".") { value.removeLast() }
        return value
    }
}

public enum HostsFileParser {
    private static let defaults: Set<String> = ["127.0.0.1 localhost", "255.255.255.255 broadcasthost", "::1 localhost",
                                                "fe80::1%lo0 localhost"]

    public static func parse(_ text: String) -> [HostsEntry] {
        var result: [HostsEntry] = []
        for (index, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let content = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            let fields = content.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard fields.count >= 2 else { continue }
            let address = fields[0]
            let names = Array(fields.dropFirst())
            let isDefault = names.allSatisfy { defaults.contains("\(address) \($0)") }
            result.append(HostsEntry(address: address, names: names, line: index + 1, isDefault: isDefault))
        }
        return result
    }
}

public enum ResolverFileParser {
    public static func parse(domain: String, text: String) -> ResolverFile {
        var servers: [String] = []
        var port: Int?
        var order: Int?
        var other: [String] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix(";") else { continue }
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            switch fields.first {
            case "nameserver" where fields.count > 1: servers.append(fields[1])
            case "port" where fields.count > 1: port = Int(fields[1])
            case "search_order" where fields.count > 1: order = Int(fields[1])
            default: other.append(line)
            }
        }
        return ResolverFile(domain: domain, nameservers: servers, port: port, searchOrder: order, otherSettings: other)
    }
}

public protocol DNSOverridesReading: Sendable {
    func overrides() -> DNSOverrides
}

/// Reads `/etc/hosts` and the files in `/etc/resolver/` directly (both are world-readable). Read-only: MacPeek never
/// edits either.
public struct FileDNSOverridesReader: DNSOverridesReading {
    private let hostsPath: String
    private let resolverDirectory: String

    public init(hostsPath: String = "/etc/hosts", resolverDirectory: String = "/etc/resolver") {
        self.hostsPath = hostsPath
        self.resolverDirectory = resolverDirectory
    }

    public func overrides() -> DNSOverrides {
        var hosts: [HostsEntry] = []
        var hostsNote: String?
        if let data = FileManager.default.contents(atPath: hostsPath) {
            hosts = HostsFileParser.parse(String(decoding: data.prefix(2_000_000), as: UTF8.self))
        } else {
            hostsNote = "\(hostsPath) could not be read."
        }

        var files: [ResolverFile] = []
        var resolverNote: String?
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: resolverDirectory, isDirectory: &isDirectory), isDirectory.boolValue {
            do {
                let names = try FileManager.default.contentsOfDirectory(atPath: resolverDirectory).filter { !$0.hasPrefix(".") }.sorted()
                for name in names.prefix(200) {
                    let path = (resolverDirectory as NSString).appendingPathComponent(name)
                    guard let data = FileManager.default.contents(atPath: path) else { continue }
                    files.append(ResolverFileParser.parse(domain: name, text: String(decoding: data.prefix(100_000), as: UTF8.self)))
                }
            } catch {
                resolverNote = "\(resolverDirectory) could not be read."
            }
        }
        return DNSOverrides(hostsEntries: hosts, hostsNote: hostsNote, resolverFiles: files, resolverNote: resolverNote)
    }
}
