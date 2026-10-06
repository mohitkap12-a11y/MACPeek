import Foundation

/// Parses `pmset -g`:
///
///     Currently in use:
///      sleep                1 (sleep prevented by useractivityd, bluetoothd, sharingd, powerd)
///      displaysleep         10
///      Sleep On Power Button 1
public enum PowerSettingsParser {
    private static let settingLine = NSRegularExpression.compile(#"^\s+([A-Za-z][A-Za-z ]*?)\s+(\d+)(?:\s+\((.*)\))?\s*$"#)
    private static let preventedBy = NSRegularExpression.compile(#"prevented by (.+)$"#)

    public static func parse(_ text: String) -> PowerSettings {
        var values: [String: Int] = [:]
        var prevented: [String: [String]] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) {
            guard let g = settingLine.groups(in: line), let name = g[1], let value = g[2].flatMap({ Int($0) }) else { continue }
            values[name] = value
            if let note = g[3], let p = preventedBy.groups(in: note), let list = p[1] {
                prevented[name] = list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            }
        }
        return PowerSettings(values: values, preventedBy: prevented)
    }
}
