import Foundation

/// Small regex helpers shared by the utility parsers (NSRegularExpression works on macOS and Linux).
public extension NSRegularExpression {
    /// Compiles a pattern that is a compile-time constant of the app; a bad pattern is a programmer error.
    static func compile(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
        do { return try NSRegularExpression(pattern: pattern, options: options) }
        catch { preconditionFailure("Invalid regular expression \(pattern): \(error)") }
    }

    /// Capture groups of the first match (index 0 is the whole match), or nil when there is no match.
    /// A group that did not participate in the match is nil.
    func groups(in text: String) -> [String?]? {
        let ns = text as NSString
        guard let match = firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            return range.location == NSNotFound ? nil : ns.substring(with: range)
        }
    }

    /// Every match as its capture groups.
    func allGroups(in text: String) -> [[String?]] {
        let ns = text as NSString
        return matches(in: text, options: [], range: NSRange(location: 0, length: ns.length)).map { match in
            (0..<match.numberOfRanges).map { index in
                let range = match.range(at: index)
                return range.location == NSNotFound ? nil : ns.substring(with: range)
            }
        }
    }
}
