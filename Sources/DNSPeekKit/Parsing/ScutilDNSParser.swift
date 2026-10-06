import Foundation

/// Parses `scutil --dns` (format verified against a real Mac):
///
///     DNS configuration
///
///     resolver #1
///       nameserver[0] : 192.168.29.1
///       if_index : 12 (en1)
///       flags    : Request A records, Request AAAA records
///       reach    : 0x00000002 (Reachable)
///
///     DNS configuration (for scoped queries)
///     resolver #1 …
public enum ScutilDNSParser {
    private struct Builder {
        var number: Int
        var nameservers: [String] = []
        var domain: String?
        var searchDomains: [String] = []
        var interface: String?
        var options: String?
        var timeout: Int?
        var flags: [String] = []
        var reachability: String?
        var order: Int?
    }

    private static let resolverHeader = NSRegularExpression.compile(#"^resolver #(\d+)\s*$"#)
    private static let keyValue = NSRegularExpression.compile(#"^\s+([A-Za-z_ ]+?)(?:\[\d+\])?\s*:\s*(.*?)\s*$"#)
    private static let interfaceName = NSRegularExpression.compile(#"\(([^)]+)\)"#)
    private static let parenthetical = NSRegularExpression.compile(#"\(([^)]*)\)"#)

    public static func parse(_ text: String) -> DNSConfiguration {
        var defaults: [DNSResolver] = []
        var scoped: [DNSResolver] = []
        var current: Builder?
        var inScoped = false

        func finish() {
            guard let b = current else { return }
            let resolver = DNSResolver(
                id: "\(inScoped ? "scoped" : "default")-\(b.number)", number: b.number, nameservers: b.nameservers,
                domain: b.domain, searchDomains: b.searchDomains, interface: b.interface, options: b.options,
                timeoutSeconds: b.timeout, flags: b.flags, reachability: b.reachability, order: b.order, isScoped: inScoped)
            if inScoped { scoped.append(resolver) } else { defaults.append(resolver) }
            current = nil
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) {
            if line.hasPrefix("DNS configuration") {
                finish()
                inScoped = line.contains("scoped")
                continue
            }
            if let g = resolverHeader.groups(in: line), let number = g[1].flatMap({ Int($0) }) {
                finish()
                current = Builder(number: number)
                continue
            }
            guard current != nil, let g = keyValue.groups(in: line), let key = g[1], let value = g[2] else { continue }
            switch key {
            case "nameserver": current?.nameservers.append(value)
            case "domain": current?.domain = value
            case "search domain": current?.searchDomains.append(value)
            case "if_index": current?.interface = interfaceName.groups(in: value)?[1] ?? value
            case "options": current?.options = value
            case "timeout": current?.timeout = Int(value)
            case "flags": current?.flags = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            case "reach": current?.reachability = parenthetical.groups(in: value)?[1] ?? value
            case "order": current?.order = Int(value)
            default: break
            }
        }
        finish()
        return DNSConfiguration(resolvers: defaults, scopedResolvers: scoped)
    }
}
