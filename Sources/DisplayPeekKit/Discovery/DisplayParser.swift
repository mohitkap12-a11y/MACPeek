import Foundation

public enum DisplayParseError: Error, Equatable, LocalizedError {
    case notJSON
    case unexpectedShape

    public var errorDescription: String? {
        switch self {
        case .notJSON: return "macOS returned display information in an unexpected format."
        case .unexpectedShape: return "macOS returned display information without a display list."
        }
    }
}

/// Parses `system_profiler SPDisplaysDataType -json`.
///
/// The shape verified against a real Mac is: `SPDisplaysDataType[]` (one entry per GPU) with a
/// `spdisplays_ndrvs[]` array of displays. Every display field is optional, because different Macs and
/// macOS versions report different keys; anything that is missing stays nil instead of being guessed.
public enum DisplayParser {
    private static let sizePattern = NSRegularExpression.compile(#"(\d+)\s*x\s*(\d+)(?:\s*@\s*([0-9.]+)\s*Hz)?"#)

    /// Keys DisplayPeek maps to dedicated fields (or deliberately hides). Everything else is shown as a detail,
    /// except anything that looks like a serial number.
    private static let consumedKeys: Set<String> = [
        "_name", "_spdisplays_displayID", "_spdisplays_pixels", "_spdisplays_resolution", "spdisplays_resolution",
        "spdisplays_pixels", "spdisplays_main", "spdisplays_mirror", "spdisplays_online", "spdisplays_pixelresolution",
        "_spdisplays_display-product-id", "_spdisplays_display-vendor-id", "_spdisplays_display-week",
        "_spdisplays_display-year", "_spdisplays_display-serial-number",
    ]

    public static func parse(_ text: String) throws -> DisplayReport {
        // The captured/command output may start with a "$ command" echo in fixtures; JSON starts at the first brace.
        guard let start = text.firstIndex(of: "{"),
              let data = String(text[start...]).data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw DisplayParseError.notJSON }
        guard let adapters = root["SPDisplaysDataType"] as? [[String: Any]] else { throw DisplayParseError.unexpectedShape }

        var gpus: [GPUInfo] = []
        var displays: [DisplayInfo] = []
        for (gpuIndex, adapter) in adapters.enumerated() {
            let gpuName = (adapter["sppci_model"] as? String) ?? (adapter["_name"] as? String) ?? "Graphics"
            gpus.append(GPUInfo(name: gpuName, cores: (adapter["sppci_cores"] as? String).flatMap(Int.init)))
            let entries = adapter["spdisplays_ndrvs"] as? [[String: Any]] ?? []
            for (index, entry) in entries.enumerated() {
                displays.append(display(entry, gpuName: gpuName, id: "\(gpuIndex)-\(index)"))
            }
        }
        return DisplayReport(gpus: gpus, displays: displays)
    }

    private static func display(_ entry: [String: Any], gpuName: String, id: String) -> DisplayInfo {
        let name = (entry["_name"] as? String)?.trimmingCharacters(in: .whitespaces)
        let looksLike = size(entry["spdisplays_resolution"] as? String ?? entry["_spdisplays_resolution"] as? String)
        let pixels = size(entry["_spdisplays_pixels"] as? String ?? entry["spdisplays_pixels"] as? String)
        let displayID = entry["_spdisplays_displayID"] as? String

        var manufactured: String?
        if let year = entry["_spdisplays_display-year"] as? String, year != "0" {
            manufactured = year
            if let week = entry["_spdisplays_display-week"] as? String, week != "0" { manufactured = "\(year), week \(week)" }
        }

        var details: [DisplayDetail] = []
        for key in entry.keys.sorted() where !consumedKeys.contains(key) {
            guard let raw = entry[key] as? String, !key.lowercased().contains("serial") else { continue }
            details.append(DisplayDetail(label: humanize(key), value: humanizeValue(raw)))
        }

        return DisplayInfo(
            id: displayID.map { "\(id)-\($0)" } ?? id,
            name: (name?.isEmpty == false ? name : nil) ?? "Display",
            gpuName: gpuName,
            nativeWidth: pixels?.width, nativeHeight: pixels?.height,
            uiWidth: looksLike?.width, uiHeight: looksLike?.height, refreshHz: looksLike?.hz,
            isMain: flag(entry["spdisplays_main"]),
            isMirrored: flag(entry["spdisplays_mirror"]),
            isOnline: flag(entry["spdisplays_online"]),
            vendorID: (entry["_spdisplays_display-vendor-id"] as? String).map { "0x" + $0 },
            productID: (entry["_spdisplays_display-product-id"] as? String).map { "0x" + $0 },
            manufactured: manufactured,
            details: details
        )
    }

    static func size(_ text: String?) -> (width: Int, height: Int, hz: Double?)? {
        guard let text, let g = sizePattern.groups(in: text),
              let w = g[1].flatMap({ Int($0) }), let h = g[2].flatMap({ Int($0) }) else { return nil }
        return (w, h, g[3].flatMap { Double($0) })
    }

    /// "spdisplays_yes" / "spdisplays_on" → true, "…_no" / "…_off" → false, anything else → nil.
    static func flag(_ value: Any?) -> Bool? {
        guard let text = (value as? String)?.lowercased() else { return nil }
        if text.hasSuffix("yes") || text.hasSuffix("_on") || text == "on" { return true }
        if text.hasSuffix("no") || text.hasSuffix("_off") || text == "off" { return false }
        return nil
    }

    static func humanize(_ key: String) -> String {
        var text = key
        for prefix in ["_spdisplays_", "spdisplays_", "sppci_"] where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
            break
        }
        return sentence(text.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " "))
    }

    static func humanizeValue(_ value: String) -> String {
        var text = value
        if text.hasPrefix("spdisplays_") { text.removeFirst("spdisplays_".count) }
        return sentence(text.replacingOccurrences(of: "_", with: " "))
    }

    private static func sentence(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
