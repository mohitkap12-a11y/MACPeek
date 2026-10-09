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
    func outdated() async throws -> HomebrewReport
}

/// Looks only at Homebrew's two standard install locations. It never installs Homebrew or edits shell configuration.
public struct StandardHomebrewLocator: HomebrewLocating {
    private let candidates: [String]
    public init(candidates: [String] = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]) {
        self.candidates = candidates
    }
    public func brewPath() -> String? { candidates.first { FileManager.default.isExecutableFile(atPath: $0) } }
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

    public func outdated() async throws -> HomebrewReport {
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
        return HomebrewReport(packages: try HomebrewParser.parse(output.stdout))
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

    /// A copyable upgrade command, only for a package that Homebrew itself just listed and whose name is well-formed.
    /// MacPeek does not run `brew upgrade`: casks can ask for a password, and that route is not verified to work without
    /// elevation, so the user runs it themselves.
    public static func action(for package: OutdatedPackage, among known: [OutdatedPackage]) -> UpdateAction? {
        guard known.contains(package), isValidPackageName(package.name) else { return nil }
        switch package.kind {
        case .formula: return .copyUpgradeCommand("brew upgrade \(package.name)")
        case .cask: return .copyUpgradeCommand("brew upgrade --cask \(package.name)")
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

    public init(os: OperatingSystemProviding, locator: HomebrewLocating, homebrew: HomebrewChecking) {
        self.os = os
        self.locator = locator
        self.homebrew = homebrew
    }

    public func operatingSystem() -> OperatingSystemInfo { os.current() }

    /// Cheap and local: is Homebrew present? Does not run it.
    public func initialHomebrewState() -> HomebrewState { locator.brewPath() == nil ? .notInstalled : .notChecked }

    public func checkHomebrew() async -> HomebrewState {
        guard locator.brewPath() != nil else { return .notInstalled }
        do {
            return .checked(try await homebrew.outdated())
        } catch is CancellationError {
            return .notChecked
        } catch let error as UpdatePeekError {
            if case .sourceUnavailable = error { return .notInstalled }
            return .failed(message: error.localizedDescription, retryable: true)
        } catch {
            return .failed(message: "Homebrew could not be checked.", retryable: true)
        }
    }
}
