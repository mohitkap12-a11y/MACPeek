import Foundation

/// One label/value pair macOS reported that DisplayPeek has no dedicated field for (rotation support, connection…).
public struct DisplayDetail: Equatable, Sendable {
    public let label: String
    public let value: String
    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public struct GPUInfo: Equatable, Sendable {
    public let name: String
    public let cores: Int?
    public init(name: String, cores: Int?) {
        self.name = name
        self.cores = cores
    }
}

/// How the desktop resolution relates to the panel's native pixels.
public enum DisplayScaling: Equatable, Sendable {
    case native
    case scaled(factor: Double)
    case unknown

    public var label: String {
        switch self {
        case .native: return "Native (1×)"
        case .scaled(let factor):
            if abs(factor - 2) < 0.01 { return "HiDPI (2×)" }
            return String(format: "Scaled (%.2g×)", factor)
        case .unknown: return "Not reported"
        }
    }
}

public struct DisplayInfo: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let gpuName: String?
    /// The panel's pixel dimensions ("3440 x 1440").
    public let nativeWidth: Int?
    public let nativeHeight: Int?
    /// The "looks like" desktop resolution, and the refresh rate macOS reports with it.
    public let uiWidth: Int?
    public let uiHeight: Int?
    public let refreshHz: Double?
    public let isMain: Bool?
    public let isMirrored: Bool?
    public let isOnline: Bool?
    public let vendorID: String?
    public let productID: String?
    public let manufactured: String?
    /// Everything else macOS reported, humanised, with serial numbers always excluded.
    public let details: [DisplayDetail]

    public init(id: String, name: String, gpuName: String? = nil,
                nativeWidth: Int? = nil, nativeHeight: Int? = nil,
                uiWidth: Int? = nil, uiHeight: Int? = nil, refreshHz: Double? = nil,
                isMain: Bool? = nil, isMirrored: Bool? = nil, isOnline: Bool? = nil,
                vendorID: String? = nil, productID: String? = nil, manufactured: String? = nil,
                details: [DisplayDetail] = []) {
        self.id = id
        self.name = name
        self.gpuName = gpuName
        self.nativeWidth = nativeWidth
        self.nativeHeight = nativeHeight
        self.uiWidth = uiWidth
        self.uiHeight = uiHeight
        self.refreshHz = refreshHz
        self.isMain = isMain
        self.isMirrored = isMirrored
        self.isOnline = isOnline
        self.vendorID = vendorID
        self.productID = productID
        self.manufactured = manufactured
        self.details = details
    }

    public var nativeResolution: String? { Self.dimensions(nativeWidth, nativeHeight) }
    public var uiResolution: String? { Self.dimensions(uiWidth, uiHeight) }

    /// "100 Hz", "59.94 Hz": trailing zeros trimmed so it reads like the spec sheet.
    public var refreshLabel: String? {
        guard let hz = refreshHz else { return nil }
        let text = hz == hz.rounded() ? String(Int(hz)) : String(format: "%.2f", hz)
        return "\(text) Hz"
    }

    public var scaling: DisplayScaling {
        guard let nativeWidth, let uiWidth, uiWidth > 0 else { return .unknown }
        let factor = Double(nativeWidth) / Double(uiWidth)
        return abs(factor - 1) < 0.01 ? .native : .scaled(factor: factor)
    }

    /// Plain text for support threads and bug reports. No serial numbers.
    public var copyText: String {
        var lines = ["Display: \(name)"]
        if let gpuName { lines.append("GPU: \(gpuName)") }
        if let nativeResolution { lines.append("Panel resolution: \(nativeResolution)") }
        if let uiResolution { lines.append("Looks like: \(uiResolution)") }
        if let refreshLabel { lines.append("Refresh rate: \(refreshLabel)") }
        if scaling != .unknown { lines.append("Scaling: \(scaling.label)") }
        if let isMain { lines.append("Main display: \(isMain ? "Yes" : "No")") }
        if let isMirrored { lines.append("Mirrored: \(isMirrored ? "Yes" : "No")") }
        if let isOnline { lines.append("Online: \(isOnline ? "Yes" : "No")") }
        if let vendorID, let productID { lines.append("Vendor / product ID: \(vendorID) / \(productID)") }
        if let manufactured { lines.append("Manufactured: \(manufactured)") }
        for detail in details { lines.append("\(detail.label): \(detail.value)") }
        return lines.joined(separator: "\n")
    }

    static func dimensions(_ w: Int?, _ h: Int?) -> String? {
        guard let w, let h else { return nil }
        return "\(w) × \(h)"
    }
}

public struct DisplayReport: Equatable, Sendable {
    public let gpus: [GPUInfo]
    public let displays: [DisplayInfo]
    public init(gpus: [GPUInfo], displays: [DisplayInfo]) {
        self.gpus = gpus
        self.displays = displays
    }
}
