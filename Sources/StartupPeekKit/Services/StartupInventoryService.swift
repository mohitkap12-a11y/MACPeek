import Foundation

/// Reads the code signature of an executable or app bundle. Read-only: it never launches the code.
public protocol CodeSignatureReading: Sendable {
    func signature(atPath path: String) -> SignatureInfo
}

/// A reader that reports nothing, used where the Security framework is unavailable and in tests.
public struct NoCodeSignatureReader: CodeSignatureReading {
    public init() {}
    public func signature(atPath path: String) -> SignatureInfo { .unavailable }
}

/// One source of startup items. A provider reports what it found and what it could not read; it never mutates anything.
public struct ProviderResult: Sendable {
    public var items: [StartupItem]
    public var limitations: [String]
    public init(items: [StartupItem] = [], limitations: [String] = []) {
        self.items = items
        self.limitations = limitations
    }
}

public protocol StartupItemProviding: Sendable {
    func items() async -> ProviderResult
}

public protocol StartupInventoryProviding: Sendable {
    func inventory() async throws -> StartupInventory
}

/// The one folder of launchd property lists a provider reads.
public struct LaunchdLocation: Sendable {
    public let path: String
    public let category: StartupCategory
    public let scope: StartupScope
    public let source: StartupSource

    public init(path: String, category: StartupCategory, scope: StartupScope, source: StartupSource) {
        self.path = path
        self.category = category
        self.scope = scope
        self.source = source
    }

    /// The conventional, readable locations. `/System/Library` is intentionally not listed: it holds macOS's own items,
    /// is sealed, and would bury the items a user can act on.
    public static func standard(home: String = NSHomeDirectory()) -> [LaunchdLocation] {
        [
            LaunchdLocation(path: home + "/Library/LaunchAgents", category: .userLaunchAgent, scope: .currentUser,
                            source: .userLaunchAgents),
            LaunchdLocation(path: "/Library/LaunchAgents", category: .systemLaunchAgent, scope: .system,
                            source: .systemLaunchAgents),
            LaunchdLocation(path: "/Library/LaunchDaemons", category: .launchDaemon, scope: .system,
                            source: .launchDaemons),
        ]
    }
}

/// Lists `*.plist` files in the given folders and parses each as untrusted data. Files that cannot be read or parsed
/// still appear (as "Status unknown") so a malformed entry is visible instead of silently missing.
public struct LaunchdPlistProvider: StartupItemProviding {
    private let locations: [LaunchdLocation]
    /// Folders are read in-process with FileManager; nothing is executed, loaded, moved or deleted.
    private let maxFilesPerFolder: Int

    public init(locations: [LaunchdLocation] = LaunchdLocation.standard(), maxFilesPerFolder: Int = 1_000) {
        self.locations = locations
        self.maxFilesPerFolder = maxFilesPerFolder
    }

    public func items() async -> ProviderResult {
        var result = ProviderResult()
        let fm = FileManager.default
        for location in locations {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: location.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            let names: [String]
            do {
                names = try fm.contentsOfDirectory(atPath: location.path)
            } catch {
                result.limitations.append("\(location.source.rawValue) could not be read, so its items are not listed.")
                continue
            }
            let plists = names.filter { $0.hasSuffix(".plist") }.sorted()
            if plists.count > maxFilesPerFolder {
                result.limitations.append("\(location.source.rawValue) has more than \(maxFilesPerFolder) files; only the first \(maxFilesPerFolder) are listed.")
            }
            for name in plists.prefix(maxFilesPerFolder) {
                if Task.isCancelled { return result }
                result.items.append(item(at: location.path + "/" + name, fileName: name, in: location))
            }
        }
        return result
    }

    private func item(at path: String, fileName: String, in location: LaunchdLocation) -> StartupItem {
        let baseName = String(fileName.dropLast(".plist".count))
        // Read one byte past the parser's limit, never the whole file: an oversized plist is rejected by the parser
        // without being loaded into memory.
        let data: Data? = FileHandle(forReadingAtPath: path).flatMap { handle in
            defer { try? handle.close() }
            return (try? handle.read(upToCount: LaunchdPlistParser.maxBytes + 1)) ?? nil
        }
        guard let data else {
            return StartupItem(id: path, name: baseName, category: location.category, scope: location.scope,
                               status: .unknown, source: location.source, propertyListPath: path,
                               observations: ["The property list could not be opened"])
        }
        do {
            let description = try LaunchdPlistParser.parse(data)
            let executable = description.executablePath
            let app = executable.flatMap(Attribution.appName(from:))
                ?? description.associatedBundleIdentifiers.first.flatMap(Attribution.appName(fromBundleIdentifier:))
            return StartupItem(id: path, name: app ?? description.label ?? baseName, label: description.label,
                               category: location.category, scope: location.scope, status: description.status,
                               source: location.source, propertyListPath: path, executablePath: executable,
                               associatedApp: app)
        } catch {
            return StartupItem(id: path, name: baseName, category: location.category, scope: location.scope,
                               status: .unknown, source: location.source, propertyListPath: path,
                               observations: ["The property list is malformed or unreadable"])
        }
    }
}

/// MacPeek's own login-item state, the only login item the public Service Management API can report on.
public enum OwnLoginItemState: Equatable, Sendable {
    case enabled, requiresApproval, notRegistered, notFound
}

public protocol OwnLoginItemReading: Sendable {
    func state() -> OwnLoginItemState?
}

public struct OwnLoginItemProvider: StartupItemProviding {
    private let reader: OwnLoginItemReading
    private let appName: String

    public init(reader: OwnLoginItemReading, appName: String = "MacPeek") {
        self.reader = reader
        self.appName = appName
    }

    public func items() async -> ProviderResult {
        guard let state = reader.state() else { return ProviderResult() }
        let status: StartupStatus
        switch state {
        case .enabled: status = .enabled
        case .requiresApproval: status = .requiresApproval
        case .notRegistered, .notFound: status = .notRegistered
        }
        let item = StartupItem(id: "service-management:main-app", name: appName, category: .loginItem,
                               scope: .currentUser, status: status, source: .serviceManagement,
                               associatedApp: appName, signature: .unavailable)
        return ProviderResult(items: [item])
    }
}

/// Combines providers, attaches signature attribution and neutral observations, flags shared labels and sorts.
public struct StartupInventoryService: StartupInventoryProviding {
    public static let completenessLimitation =
        "Items listed under Login Items & Extensions in System Settings, including apps allowed to run in the background, cannot be listed by other apps through public macOS APIs. Open System Settings to review them."
    public static let systemLimitation =
        "macOS's own startup items in /System/Library are not listed."

    private let providers: [StartupItemProviding]
    private let signatures: CodeSignatureReading
    private let maxSignatureChecks: Int
    private let home: String

    public init(providers: [StartupItemProviding], signatures: CodeSignatureReading = NoCodeSignatureReader(),
                maxSignatureChecks: Int = 400, home: String = NSHomeDirectory()) {
        self.providers = providers
        self.signatures = signatures
        self.maxSignatureChecks = maxSignatureChecks
        self.home = home
    }

    public func inventory() async throws -> StartupInventory {
        var items: [StartupItem] = []
        var limitations: [String] = []
        for provider in providers {
            let result = await provider.items()
            items.append(contentsOf: result.items)
            limitations.append(contentsOf: result.limitations)
        }
        try Task.checkCancellation()

        var checked = 0
        items = try items.map { item in
            try Task.checkCancellation()
            guard let executable = item.executablePath else {
                // Only a parsed property list can be said not to name an executable; items with no property list
                // (MacPeek's own login item) or one that could not be read already carry their own explanation.
                guard item.propertyListPath != nil, item.observations.isEmpty else { return item }
                return item.replacing(observations: Attribution.observations(
                    executablePath: nil, signature: item.signature, executableExists: nil, home: home))
            }
            let exists = FileManager.default.fileExists(atPath: executable)
            var signature = item.signature
            if exists, checked < maxSignatureChecks {
                checked += 1
                signature = signatures.signature(atPath: Attribution.enclosingAppBundle(of: executable) ?? executable)
            }
            let notes = item.observations + Attribution.observations(
                executablePath: executable, signature: signature, executableExists: exists, home: home)
            return item.replacing(signature: signature, observations: notes)
        }
        if checked >= maxSignatureChecks {
            limitations.append("Developer signatures were read for the first \(maxSignatureChecks) items only.")
        }

        items = Self.flagSharedLabels(items)
        items.sort(by: Self.order)
        limitations.append(Self.systemLimitation)
        limitations.append(Self.completenessLimitation)
        return StartupInventory(items: items, limitations: limitations)
    }

    /// Two files can claim the same label; both stay listed and each says so.
    static func flagSharedLabels(_ items: [StartupItem]) -> [StartupItem] {
        let counts = Dictionary(grouping: items.compactMap(\.label), by: { $0 }).mapValues(\.count)
        return items.map { item in
            guard let label = item.label, (counts[label] ?? 0) > 1 else { return item }
            return item.replacing(observations: item.observations + ["Another item uses the same label"])
        }
    }

    static func order(_ a: StartupItem, _ b: StartupItem) -> Bool {
        let categories = StartupCategory.allCases
        let ai = categories.firstIndex(of: a.category) ?? categories.count
        let bi = categories.firstIndex(of: b.category) ?? categories.count
        if ai != bi { return ai < bi }
        let order = a.name.localizedCaseInsensitiveCompare(b.name)
        return order == .orderedSame ? a.id < b.id : order == .orderedAscending
    }
}

public enum StartupSearch {
    /// Case-insensitive match on name, label, app, paths and signing team. An empty query returns everything.
    public static func filter(_ items: [StartupItem], query: String) -> [StartupItem] {
        let terms = query.split(whereSeparator: \.isWhitespace).map { $0.lowercased() }
        guard !terms.isEmpty else { return items }
        return items.filter { item in
            var team = ""
            if case .signed(let id?, _) = item.signature { team = id }
            let haystack = [item.name, item.label, item.associatedApp, item.executablePath, item.propertyListPath, team,
                            item.category.label]
                .compactMap { $0 }.joined(separator: "\n").lowercased()
            return terms.allSatisfy { haystack.contains($0) }
        }
    }
}
