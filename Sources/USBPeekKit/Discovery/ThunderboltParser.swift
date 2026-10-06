import Foundation

/// Parses `system_profiler SPThunderboltDataType -json`.
///
/// Verified shape: `SPThunderboltDataType[]`, one entry per Thunderbolt/USB4 bus, each with
/// `receptacle_<n>_tag` objects (`receptacle_id_key`, `current_speed_key`, `receptacle_status_key`).
/// When a device is attached macOS adds `_items`; only the device names are read from those.
public enum ThunderboltParser {
    public static func parse(_ text: String) -> [ThunderboltPort]? {
        guard let start = text.firstIndex(of: "{"),
              let data = String(text[start...]).data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        guard let buses = root["SPThunderboltDataType"] as? [[String: Any]] else { return nil }

        var ports: [ThunderboltPort] = []
        for (busIndex, bus) in buses.enumerated() {
            let busName = (bus["_name"] as? String).map(humanizeBus) ?? "Thunderbolt bus \(busIndex + 1)"
            let devices = deviceNames(in: bus["_items"])
            for key in bus.keys.sorted() where key.hasPrefix("receptacle_") && key.hasSuffix("_tag") {
                guard let tag = bus[key] as? [String: Any] else { continue }
                let rawStatus = tag["receptacle_status_key"] as? String ?? ""
                let connected = !rawStatus.isEmpty && !rawStatus.contains("no_devices")
                ports.append(ThunderboltPort(
                    id: "\(busIndex)-\(key)",
                    busName: busName,
                    receptacle: tag["receptacle_id_key"] as? String,
                    speed: tag["current_speed_key"] as? String,
                    status: statusLabel(rawStatus),
                    isConnected: connected,
                    connectedDevices: connected ? devices : []
                ))
            }
        }
        return ports
    }

    /// "thunderboltusb4_bus_1" → "Thunderbolt / USB4 bus 1".
    static func humanizeBus(_ name: String) -> String {
        if let number = name.split(separator: "_").last, Int(number) != nil, name.lowercased().contains("bus") {
            return "Thunderbolt / USB4 bus \(number)"
        }
        return name
    }

    static func statusLabel(_ raw: String) -> String {
        if raw.isEmpty { return "Status not reported" }
        if raw.contains("no_devices") { return "No device connected" }
        let words = raw.replacingOccurrences(of: "receptacle_", with: "").replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    private static func deviceNames(in items: Any?) -> [String] {
        guard let list = items as? [[String: Any]] else { return [] }
        return list.flatMap { item -> [String] in
            let name = (item["device_name_key"] as? String) ?? (item["_name"] as? String)
            return (name.map { [$0] } ?? []) + deviceNames(in: item["_items"])
        }
    }
}
