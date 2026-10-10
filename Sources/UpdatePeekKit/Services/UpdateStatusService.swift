import Foundation
import MacPeekCore

public protocol OperatingSystemProviding: Sendable {
    func current() -> OperatingSystemInfo
}

public protocol HomebrewLocating: Sendable {
    /// Absolute path of an existing, executable `brew`, or nil when Homebrew is not installed.
    func brewPath() -> String?
}

public protocol HomebrewChecking: Sendable {
    func outdated() async throws -> PackageReport
}

public protocol NpmLocating: Sendable {
    /// Absolute path of an existing, executable `npm`, or nil when it was not found in a standard location.
    func npmPath() -> String?
}

public protocol NpmChecking: Sendable {
    func outdated() async throws -> PackageReport
}

/// Looks only at Homebrew's two standard install locations. It never installs Homebrew or edits shell configuration.
public struct StandardHomebrewLocator: HomebrewLocating {
    private let candidates: [String]
    public init(candidates: [String] = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]) {
        self.candidates = candidates
    }
    public func brewPath() -> String? { candidates.first { FileManager.default.isExecutableFile(atPath: $0) } }
}

/// Looks only at the two standard locations npm is installed to by Homebrew's `node` and by the nodejs.org installer.
/// Version managers (nvm, fnm, Volta) keep npm elsewhere and are not detected. Never installs Node or edits shell config.
public struct StandardNpmLocator: NpmLocating {
    private let candidates: [String]
    public init(candidates: [String] = ["/opt/homebrew/bin/npm", "/usr/local/bin/npm"]) {
        self.candidates = candidates
    }
    public func npmPath() -> String? { candidates.first { FileManager.default.isExecutableFile(atPath: $0) } }
}

/// Runs `brew outdated --json=v2` read-only: a fixed executable and a fixed argument array (no shell), with Homebrew's
/// auto-update and analytics switched off so the check starts no network work of its own.
/// `/usr/bin/env` only sets those variables for the one child process.
public struct BrewOutdatedChecker: HomebrewChecking {
    private let runner: CommandRunning
    private let locator: HomebrewLocating

    public init(runner: CommandRunning = ShellCommand(timeout: 60), locator: HomebrewLocating = StandardHomebrewLocator()) {
        self.runner = runner
        self.locator = locator
    }

    static func arguments(brew: String) -> [String] {
        ["HOMEBREW_NO_AUTO_UPDATE=1", "HOMEBREW_NO_ANALYTICS=1", "HOMEBREW_NO_ENV_HINTS=1", brew, "outdated", "--json=v2"]
    }

    public func outdated() async throws -> PackageReport {
        guard let brew = locator.brewPath() else { throw UpdatePeekError.sourceUnavailable("Homebrew is not installed.") }
        let output: CommandOutput
        do {
            output = try await runner.run("/usr/bin/env", Self.arguments(brew: brew))
        } catch let error as CommandError {
            throw UpdatePeekError.operationFailed(error.localizedDescription)
        }
        guard output.status == 0 else {
            throw UpdatePeekError.operationFailed("Homebrew could not list outdated packages.")
        }
        return PackageReport(packages: try HomebrewParser.parse(output.stdout))
    }
}

/// Runs `npm outdated --global --json`: a fixed executable and a fixed argument array (no shell). Unlike Homebrew, npm asks
/// its registry (npmjs.org unless the user's own npm config says otherwise), so this makes network requests and only runs
/// when the user presses Check. npm is a script that needs `node`; an app launched from the menu bar has a minimal PATH,
/// so the child gets npm's own directory first, where Homebrew and the nodejs.org installer put `node` too.
public struct NpmOutdatedChecker: NpmChecking {
    private let runner: CommandRunning
    private let locator: NpmLocating

    public init(runner: CommandRunning = ShellCommand(timeout: 90), locator: NpmLocating = StandardNpmLocator()) {
        self.runner = runner
        self.locator = locator
    }

    static func arguments(npm: String) -> [String] {
        let directory = URL(fileURLWithPath: npm).deletingLastPathComponent().path
        return ["PATH=\(directory):/usr/bin:/bin:/usr/sbin:/sbin", "npm_config_update_notifier=false", "npm_config_fund=false",
                npm, "outdated", "--global", "--json"]
    }

    public func outdated() async throws -> PackageReport {
        guard let npm = locator.npmPath() else { throw UpdatePeekError.sourceUnavailable("npm was not found.") }
        let output: CommandOutput
        do {
            output = try await runner.run("/usr/bin/env", Self.arguments(npm: npm))
        } catch let error as CommandError {
            throw UpdatePeekError.operationFailed(error.localizedDescription)
        }
        // npm exits 1 when it found outdated packages (and also when it failed), so the exit code alone says nothing.
        guard output.status == 0 || output.status == 1 else { throw UpdatePeekError.operationFailed(NpmParser.failureMessage) }
        let trimmed = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if output.status == 0 { return PackageReport(packages: []) }
            throw UpdatePeekError.operationFailed(NpmParser.failureMessage)
        }
        do {
            return PackageReport(packages: try NpmParser.parse(trimmed))
        } catch UpdatePeekError.malformedData {
            throw UpdatePeekError.operationFailed("npm's answer could not be understood.")
        }
    }
}

/// Decides which actions exist for an item. Nothing here runs a command.
public enum UpdateActions {
    /// Package names Homebrew can have: letters, digits and `@ . _ + - /`; never starting with `-` (option injection).
    static func isValidPackageName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first, first != "-", name.count <= 200 else { return false }
        return name.unicodeScalars.allSatisfy { scalar in
            (scalar.value < 128 && (CharacterSet.alphanumerics.contains(scalar) || "@._+-/".unicodeScalars.contains(scalar)))
        }
    }

    /// npm names: lowercase letters, digits and `- . _ ~`, optionally scoped (`@scope/name`); a part never starts with
    /// `.`, `_` or `-` (option injection). Old packages with capitals get no copy button; they are still listed.
    static func isValidNpmPackageName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 214 else { return false }
        func isValidPart(_ part: Substring) -> Bool {
            guard let first = part.unicodeScalars.first, first != ".", first != "_", first != "-" else { return false }
            return part.unicodeScalars.allSatisfy { scalar in
                (scalar.value >= 97 && scalar.value <= 122) || (scalar.value >= 48 && scalar.value <= 57)
                    || "-._~".unicodeScalars.contains(scalar)
            }
        }
        if name.hasPrefix("@") {
            let parts = name.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
            return parts.count == 2 && parts.allSatisfy { isValidPart($0) }
        }
        return isValidPart(Substring(name))
    }

    /// A copyable upgrade command, only for a package that its package manager just listed and whose name is well-formed.
    /// MacPeek does not run `brew upgrade` or `npm install`: casks can ask for a password, global npm installs can need
    /// elevated rights depending on how Node was installed, and neither route is verified to work without elevation, so
    /// the user runs the command themselves.
    public static func action(for package: OutdatedPackage, among known: [OutdatedPackage]) -> UpdateAction? {
        guard known.contains(package) else { return nil }
        switch package.kind {
        case .formula:
            return isValidPackageName(package.name) ? .copyUpgradeCommand("brew upgrade \(package.name)") : nil
        case .cask:
            return isValidPackageName(package.name) ? .copyUpgradeCommand("brew upgrade --cask \(package.name)") : nil
        case .npm:
            return isValidNpmPackageName(package.name) ? .copyUpgradeCommand("npm install -g \(package.name)@latest") : nil
        }
    }
}

/// The macOS version is always known locally. MacPeek does not check whether a macOS update exists: `softwareupdate --list`
/// output is not a stable API and was not verified on every supported version, so the honest answer is "open Software Update".
public struct UpdateStatusService: Sendable {
    public static let osUpdateNotice =
        "MacPeek does not check for macOS updates. Open Software Update to see what Apple offers for this Mac."
    public static let otherAppsNotice =
        "Other apps: update status unavailable. No supported update source is available for them, so they are not checked."

    private let os: OperatingSystemProviding
    private let locator: HomebrewLocating
    private let homebrew: HomebrewChecking
    private let npmLocator: NpmLocating
    private let npm: NpmChecking

    public init(os: OperatingSystemProviding, locator: HomebrewLocating, homebrew: HomebrewChecking,
                npmLocator: NpmLocating, npm: NpmChecking) {
        self.os = os
        self.locator = locator
        self.homebrew = homebrew
        self.npmLocator = npmLocator
        self.npm = npm
    }

    public func operatingSystem() -> OperatingSystemInfo { os.current() }

    /// Cheap and local: is Homebrew present? Does not run it.
    public func initialHomebrewState() -> PackageCheckState { locator.brewPath() == nil ? .notInstalled : .notChecked }

    public func checkHomebrew() async -> PackageCheckState {
        guard locator.brewPath() != nil else { return .notInstalled }
        return await state(failure: "Homebrew could not be checked.") { try await homebrew.outdated() }
    }

    /// Cheap and local: was npm found in a standard location? Does not run it.
    public func initialNpmState() -> PackageCheckState { npmLocator.npmPath() == nil ? .notInstalled : .notChecked }

    /// Asks npm's registry (a network request), so it only runs when the user presses Check.
    public func checkNpm() async -> PackageCheckState {
        guard npmLocator.npmPath() != nil else { return .notInstalled }
        return await state(failure: "npm could not be checked.") { try await npm.outdated() }
    }

    private func state(failure: String, _ check: () async throws -> PackageReport) async -> PackageCheckState {
        do {
            return .checked(try await check())
        } catch is CancellationError {
            return .notChecked
        } catch let error as UpdatePeekError {
            if case .sourceUnavailable = error { return .notInstalled }
            return .failed(message: error.localizedDescription, retryable: true)
        } catch {
            return .failed(message: failure, retryable: true)
        }
    }
}
