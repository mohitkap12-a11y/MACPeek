import Foundation

public struct OperatingSystemInfo: Equatable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    /// The OS build ("24B83"), nil when macOS did not report it.
    public let build: String?

    public init(major: Int, minor: Int, patch: Int, build: String?) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.build = build.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// "15.1" or "15.1.1": a zero patch level is omitted, as macOS itself shows it.
    public var versionString: String {
        patch == 0 ? "\(major).\(minor)" : "\(major).\(minor).\(patch)"
    }

    public var displayString: String {
        build.map { "macOS \(versionString) (\($0))" } ?? "macOS \(versionString)"
    }
}

public enum PackageKind: String, Equatable, Sendable {
    case formula, cask
    /// A globally installed npm package (`npm outdated -g`).
    case npm

    public var label: String {
        switch self {
        case .formula: return "Formula"
        case .cask: return "Cask"
        case .npm: return "npm"
        }
    }
}

/// A package a package manager lists as outdated, exactly as it reported it. For npm, `currentVersion` is npm's `latest`.
public struct OutdatedPackage: Identifiable, Equatable, Sendable {
    public let name: String
    public let kind: PackageKind
    public let installedVersions: [String]
    public let currentVersion: String

    public var id: String { "\(kind.rawValue):\(name)" }

    public init(name: String, kind: PackageKind, installedVersions: [String], currentVersion: String) {
        self.name = name
        self.kind = kind
        self.installedVersions = installedVersions
        self.currentVersion = currentVersion
    }

    public var installedLabel: String { installedVersions.isEmpty ? "Not reported" : installedVersions.joined(separator: ", ") }
}

/// What a package manager reported and when. Homebrew answers from its last-fetched index (MacPeek never runs
/// `brew update`); npm compares with the registry at the time of the check.
public struct PackageReport: Equatable, Sendable {
    public let packages: [OutdatedPackage]
    public let checkedAt: Date
    public init(packages: [OutdatedPackage], checkedAt: Date = Date()) {
        self.packages = packages
        self.checkedAt = checkedAt
    }
}

public enum PackageCheckState: Equatable, Sendable {
    case notInstalled
    case notChecked
    case checking
    case checked(PackageReport)
    case failed(message: String, retryable: Bool)
}

public enum UpdatePeekError: Error, LocalizedError, Equatable {
    case sourceUnavailable(String)
    case malformedData
    case operationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .sourceUnavailable(let detail): return detail
        case .malformedData: return "Homebrew's answer could not be understood."
        case .operationFailed(let detail): return detail
        }
    }
}

/// What the user can do about an update. Only actions that need no elevation and no extra permission exist here.
public enum UpdateAction: Equatable, Sendable {
    /// Open System Settings → Software Update.
    case openSoftwareUpdate
    /// Copy a fixed command for the user to run in Terminal themselves. MacPeek does not run it.
    case copyUpgradeCommand(String)
}
