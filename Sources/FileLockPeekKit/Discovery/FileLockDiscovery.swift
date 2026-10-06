import Foundation
import MacPeekCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Source of truth for "what is holding this path". UI code depends on this, never on lsof output.
public protocol FileLockDiscoveryProtocol: Sendable {
    func holders(of path: String) async throws -> [FileLockHolder]
}

public enum FileLockError: Error, LocalizedError, Equatable {
    case invalidPath(String)
    case notFound(String)
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPath(let reason): return reason
        case .notFound(let path): return "There is no file or folder at “\(path)”."
        case .commandFailed(let detail): return "The scan failed: \(detail)"
        }
    }
}

/// Finds holders of a file or folder with `lsof`, for the current user's processes only.
/// The path is passed as a separate argument (never through a shell) and must be absolute.
public struct LsofFileLockDiscovery: FileLockDiscoveryProtocol {
    static let baseArguments = ["-nP", "+c", "0", "-FpcLfaltn"]

    private let runner: CommandRunning
    private let lsofPath: String
    private let ownPID: Int

    public init(
        runner: CommandRunning = ShellCommand(timeout: 30), // folder scans are recursive and can be slow
        lsofPath: String = "/usr/sbin/lsof",
        ownPID: Int = Int(getpid())
    ) {
        self.runner = runner
        self.lsofPath = lsofPath
        self.ownPID = ownPID
    }

    public func holders(of path: String) async throws -> [FileLockHolder] {
        guard path.hasPrefix("/") else { throw FileLockError.invalidPath("Enter a full path that starts with “/”.") }
        guard !path.contains("\0") else { throw FileLockError.invalidPath("That path contains an invalid character.") }

        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved, isDirectory: &isDirectory) else {
            throw FileLockError.notFound(path)
        }
        // A file: exact matches. A folder: everything open beneath it (+D is recursive; a hung scan is cancelled).
        let arguments = Self.baseArguments + (isDirectory.boolValue ? ["+D", resolved] : ["--", resolved])

        let output: CommandOutput
        do {
            output = try await runner.run(lsofPath, arguments)
        } catch {
            throw FileLockError.commandFailed(error.localizedDescription)
        }
        // Same rule as PortPeek: status 1 means "nothing matched" (also when others matched); status > 1,
        // or status 1 with no data and an error, is a real failure that must never read as "nothing holds it".
        let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if output.status > 1 || (output.status == 1 && output.stdout.isEmpty && !detail.isEmpty) {
            throw FileLockError.commandFailed(detail.isEmpty ? "lsof exited with status \(output.status)" : detail)
        }
        return FileHolderParser.parse(output.stdout, excludingPID: ownPID)
    }
}
