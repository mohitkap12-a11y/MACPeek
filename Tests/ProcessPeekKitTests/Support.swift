import Foundation
import MacPeekCore
import PortPeekKit

func fixture(_ name: String) throws -> String {
    guard let url = Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures") else {
        throw NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing \(name)"])
    }
    return try String(contentsOf: url, encoding: .utf8)
}

/// Returns canned output per call (keyed by the first argument) and records what it was asked to run.
final class ScriptedRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [(String, [String])] = []
    var results: [String: Result<CommandOutput, Error>]
    init(_ results: [String: Result<CommandOutput, Error>]) { self.results = results }
    var calls: [(String, [String])] { lock.lock(); defer { lock.unlock() }; return _calls }
    private func record(_ executable: String, _ arguments: [String]) {
        lock.lock(); defer { lock.unlock() }
        _calls.append((executable, arguments))
    }
    func run(_ executable: String, _ arguments: [String]) async throws -> CommandOutput {
        record(executable, arguments)
        guard let result = results[arguments.first ?? ""] else { return CommandOutput(stdout: "", stderr: "unscripted", status: 1) }
        return try result.get()
    }
}

func ok(_ text: String) -> Result<CommandOutput, Error> { .success(CommandOutput(stdout: text, stderr: "", status: 0)) }
func failed(_ stderr: String, status: Int32 = 1) -> Result<CommandOutput, Error> { .success(CommandOutput(stdout: "", stderr: stderr, status: status)) }

struct FakePorts: PortDiscoveryProtocol {
    let result: Result<[PortInfo], Error>
    func discover() async throws -> [PortInfo] { try result.get() }
}
