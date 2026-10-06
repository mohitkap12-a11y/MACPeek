import Foundation

/// `dscacheutil -q host -a name apple.com` (format verified against a real Mac):
///
///     name: apple.com
///     ipv6_address: 2620:149:af0::10
///
///     name: apple.com
///     ip_address: 17.253.144.10
public enum DSCacheUtilParser {
    public static func addresses(_ text: String) -> [String] {
        text.split(separator: "\n").compactMap { line -> String? in
            for prefix in ["ip_address:", "ipv6_address:"] where line.hasPrefix(prefix) {
                let value = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
            return nil
        }
    }
}

/// `dig @server name A +time=2 +tries=1`. The dig output format is documented but was NOT captured from a real Mac
/// when this was written (see docs/utilities/dnspeek.md); anything unrecognised is reported as such, never guessed.
public enum DigParser {
    private static let status = NSRegularExpression.compile(#"status:\s*([A-Z]+)"#)
    private static let answers = NSRegularExpression.compile(#"ANSWER:\s*(\d+)"#)
    private static let queryTime = NSRegularExpression.compile(#"Query time:\s*(\d+)\s*msec"#)

    public static func outcome(output: String, status code: Int32) -> ServerProbe.Outcome {
        let lower = output.lowercased()
        if lower.contains("timed out") || lower.contains("no servers could be reached") { return .timedOut }
        guard let st = status.groups(in: output)?[1] else {
            return .unavailable(code == 0 ? "dig printed an answer MacPeek does not understand." : "dig failed (status \(code)).")
        }
        let count = answers.groups(in: output)?[1].flatMap { Int($0) } ?? 0
        let ms = queryTime.groups(in: output)?[1].flatMap { Int($0) }
        return .answered(queryMilliseconds: ms, status: st, answers: count)
    }
}
