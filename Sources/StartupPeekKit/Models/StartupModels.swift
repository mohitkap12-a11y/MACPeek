import Foundation

/// What kind of startup mechanism an entry comes from. StartupPeek labels this on every row because macOS has several
/// mechanisms and no single complete list.
public enum StartupCategory: String, Sendable, CaseIterable {
    case loginItem, backgroundItem, userLaunchAgent, systemLaunchAgent, launchDaemon, unknown

    public var label: String {
        switch self {
        case .loginItem: return "Login Item"
        case .backgroundItem: return "Background Item"
        case .userLaunchAgent: return "User Launch Agent"
        case .systemLaunchAgent: return "System Launch Agent"
        case .launchDaemon: return "Launch Daemon"
        case .unknown: return "Unknown"
        }
    }

    public var sectionTitle: String {
        switch self {
        case .loginItem: return "Login items"
        case .backgroundItem: return "Background items"
        case .userLaunchAgent: return "User launch agents"
        case .systemLaunchAgent: return "System launch agents"
        case .launchDaemon: return "Launch daemons"
        case .unknown: return "Other"
        }
    }

    /// Plain-language meaning of the category.
    public var explanation: String {
        switch self {
        case .loginItem: return "An app or helper that opens when you log in."
        case .backgroundItem: return "A helper that an app has registered to run in the background."
        case .userLaunchAgent: return "A background job that starts for your account, defined by a file in your Library folder."
        case .systemLaunchAgent: return "A background job that starts for every user who logs in, defined by a file in /Library."
        case .launchDaemon: return "A background job that macOS starts at boot, before anyone logs in, defined by a file in /Library."
        case .unknown: return "macOS did not report what kind of item this is."
        }
    }
}

public enum StartupScope: String, Sendable {
    case currentUser, system

    public var label: String { self == .currentUser ? "Current user" : "System-wide" }
}

public enum StartupStatus: Equatable, Sendable {
    case enabled
    case requiresApproval
    case notRegistered
    /// A launchd property list that asks to start at load or to be kept running.
    case startsAutomatically
    /// A launchd property list that starts only when something triggers it (a socket, a timer, a watched path).
    case startsOnDemand
    /// The property list itself contains `Disabled = true`. launchd's separate override database is not read.
    case disabledInFile
    case unknown

    public var label: String {
        switch self {
        case .enabled: return "Enabled"
        case .requiresApproval: return "Requires approval"
        case .notRegistered: return "Not registered"
        case .startsAutomatically: return "Starts automatically"
        case .startsOnDemand: return "Starts on demand"
        case .disabledInFile: return "Disabled in file"
        case .unknown: return "Status unknown"
        }
    }
}

/// What the code signature says. Read from the signature only; whether it is trusted or valid is not checked.
public enum SignatureInfo: Equatable, Sendable {
    case signed(teamID: String?, identifier: String?)
    case unsigned
    case unavailable

    public var summary: String {
        switch self {
        case .signed(let team?, _): return "Signing team ID \(team) (read from the signature, not validated)"
        case .signed(nil, _): return "Signed, with no team identifier"
        case .unsigned: return "Developer signature unavailable (not signed)"
        case .unavailable: return "Developer signature unavailable"
        }
    }
}

/// How an item was found, shown on every row.
public enum StartupSource: String, Sendable {
    case serviceManagement = "Service Management (this app only)"
    case userLaunchAgents = "~/Library/LaunchAgents"
    case systemLaunchAgents = "/Library/LaunchAgents"
    case launchDaemons = "/Library/LaunchDaemons"
    case other = "Other"
}

public struct StartupItem: Identifiable, Equatable, Sendable {
    /// Unique per source file (or per fixed item), never derived from the label: labels are not guaranteed unique.
    public let id: String
    public let name: String
    public let label: String?
    public let category: StartupCategory
    public let scope: StartupScope
    public let status: StartupStatus
    public let source: StartupSource
    public let propertyListPath: String?
    public let executablePath: String?
    /// App name inferred from the executable path or the `AssociatedBundleIdentifiers` key. Always an inference.
    public let associatedApp: String?
    public let signature: SignatureInfo
    /// Neutral observations ("Path is outside common application locations"). Never a verdict.
    public let observations: [String]

    public init(id: String, name: String, label: String? = nil, category: StartupCategory, scope: StartupScope,
                status: StartupStatus, source: StartupSource, propertyListPath: String? = nil,
                executablePath: String? = nil, associatedApp: String? = nil,
                signature: SignatureInfo = .unavailable, observations: [String] = []) {
        self.id = id
        self.name = name
        self.label = label
        self.category = category
        self.scope = scope
        self.status = status
        self.source = source
        self.propertyListPath = propertyListPath
        self.executablePath = executablePath
        self.associatedApp = associatedApp
        self.signature = signature
        self.observations = observations
    }

    public func replacing(signature: SignatureInfo? = nil, observations: [String]? = nil) -> StartupItem {
        StartupItem(id: id, name: name, label: label, category: category, scope: scope, status: status, source: source,
                    propertyListPath: propertyListPath, executablePath: executablePath, associatedApp: associatedApp,
                    signature: signature ?? self.signature, observations: observations ?? self.observations)
    }

    /// "Likely associated with Example" — an inference, worded as one.
    public var attributionLine: String? {
        associatedApp.map { "Likely associated with \($0)" }
    }

    public var copyText: String {
        var lines = ["\(name)", "Type: \(category.label)", "Scope: \(scope.label)", "Status: \(status.label)",
                     "Found via: \(source.rawValue)"]
        if let label { lines.append("Label: \(label)") }
        if let executablePath { lines.append("Executable: \(executablePath)") }
        if let propertyListPath { lines.append("Property list: \(propertyListPath)") }
        if let attributionLine { lines.append(attributionLine) }
        lines.append(signature.summary)
        lines.append(contentsOf: observations)
        return lines.joined(separator: "\n")
    }
}

/// The inventory plus what it could not see. `limitations` is always shown: no list here is claimed to be complete.
public struct StartupInventory: Equatable, Sendable {
    public let items: [StartupItem]
    public let limitations: [String]
    public let updatedAt: Date

    public init(items: [StartupItem], limitations: [String], updatedAt: Date = Date()) {
        self.items = items
        self.limitations = limitations
        self.updatedAt = updatedAt
    }

    public func items(in category: StartupCategory) -> [StartupItem] { items.filter { $0.category == category } }
}

public enum StartupPeekError: Error, LocalizedError, Equatable {
    case malformedPropertyList
    case operationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .malformedPropertyList: return "The property list could not be read."
        case .operationFailed(let detail): return detail
        }
    }
}
