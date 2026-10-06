import Foundation

/// Parses `ioreg -p IOUSB -l -w0` (the text format verified against a real Mac).
///
/// Layout: each registry entry is a line `<prefix>+-o Name@location  <class Foo, id 0x…, …>` followed by a
/// `{ … }` block of `"key" = value` lines. The column of `+-o` gives the depth (two columns per level).
/// Controllers sit at depth 1; devices (`IOUSBHostDevice`) hang below them, hubs containing their children.
///
/// Privacy: properties whose key mentions "serial" are dropped at the line level, so a serial number never
/// enters any model. Only a short allow-list of keys is kept in any case.
public enum IORegUSBParser {
    private struct Node {
        var depth: Int
        var name: String
        var location: String?
        var className: String
        var registryID: String
        var props: [String: String] = [:]
        var children: [Node] = []
    }

    private static let header = NSRegularExpression.compile(
        #"\+-o (.*?)(?:@([0-9A-Fa-f]+))?\s+<class ([A-Za-z0-9_]+)(?:,\s+id (0x[0-9a-fA-F]+))?"#)
    private static let property = NSRegularExpression.compile(#"^[ |]*"([^"]+)" = (.+?)\s*$"#)

    private static let keptKeys: Set<String> = [
        "USB Product Name", "kUSBProductString", "USB Vendor Name", "kUSBVendorString", "idVendor", "idProduct",
        "UsbLinkSpeed", "bcdUSB", "bDeviceClass", "locationID",
    ]
    private static let deviceClasses: Set<String> = ["IOUSBHostDevice", "IOUSBDevice"]

    public static func parse(_ text: String) -> [USBBus] {
        let roots = buildTree(text)
        // Controllers are the entries directly under the registry root.
        let controllers = roots.flatMap { $0.depth == 0 ? $0.children : [$0] }
        return controllers.map { controller in
            USBBus(
                id: controller.registryID,
                busNumber: controller.location.flatMap(busNumber),
                controllerClass: controller.className,
                devices: controller.children.flatMap(devices)
            )
        }
    }

    // MARK: Tree

    private static func buildTree(_ text: String) -> [Node] {
        var roots: [Node] = []
        var stack: [Node] = []

        func closeTop() {
            let finished = stack.removeLast()
            if stack.isEmpty { roots.append(finished) } else { stack[stack.count - 1].children.append(finished) }
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) {
            if let marker = line.range(of: "+-o "), let g = header.groups(in: line) {
                let depth = line.distance(from: line.startIndex, to: marker.lowerBound) / 2
                while let top = stack.last, top.depth >= depth { closeTop() }
                let name = (g[1] ?? "").trimmingCharacters(in: .whitespaces)
                stack.append(Node(depth: depth, name: name, location: g[2], className: g[3] ?? "", registryID: g[4] ?? "\(name)@\(g[2] ?? "")"))
            } else if !stack.isEmpty, let g = property.groups(in: line), let key = g[1], let value = g[2],
                      keptKeys.contains(key), !key.lowercased().contains("serial") {
                stack[stack.count - 1].props[key] = stringValue(value)
            }
        }
        while !stack.isEmpty { closeTop() }
        return roots
    }

    /// Strings are unquoted, integers kept as digits; dictionaries, data and everything else are ignored.
    private static func stringValue(_ raw: String) -> String? {
        if raw.hasPrefix("\""), raw.hasSuffix("\""), raw.count >= 2 { return String(raw.dropFirst().dropLast()) }
        if Int(raw) != nil { return raw }
        return nil
    }

    // MARK: Devices

    private static func devices(_ node: Node) -> [USBDevice] {
        let below = node.children.flatMap(devices)
        guard deviceClasses.contains(node.className) else { return below }  // pass through non-device entries
        let p = node.props
        let name = clean(p["USB Product Name"]) ?? clean(p["kUSBProductString"]) ?? clean(node.name) ?? "USB device"
        let vendor = clean(p["USB Vendor Name"]) ?? clean(p["kUSBVendorString"])
        let location = p["locationID"].flatMap { Int($0) }
        return [USBDevice(
            id: node.registryID,
            name: name,
            vendorName: vendor,
            vendorID: p["idVendor"].flatMap { Int($0) },
            productID: p["idProduct"].flatMap { Int($0) },
            linkSpeedBitsPerSecond: p["UsbLinkSpeed"].flatMap { Double($0) },
            declaredUSBVersion: p["bcdUSB"].flatMap { Int($0) }.map(versionLabel),
            deviceClass: p["bDeviceClass"].flatMap { Int($0) },
            locationID: location,
            children: below
        )]
    }

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// bcdUSB is binary-coded decimal: 0x0320 (800) is USB 3.20, 0x0210 (528) is USB 2.10.
    static func versionLabel(_ bcd: Int) -> String {
        let major = (bcd >> 8) & 0xFF
        let minor = (bcd >> 4) & 0x0F
        let patch = bcd & 0x0F
        return patch == 0 ? "\(major).\(minor)0" : "\(major).\(minor)\(patch)"
    }

    /// The top byte of a hex location ("02000000") is the bus number.
    private static func busNumber(_ location: String) -> Int? {
        guard location.count >= 2 else { return nil }
        return Int(location.prefix(2), radix: 16)
    }
}
