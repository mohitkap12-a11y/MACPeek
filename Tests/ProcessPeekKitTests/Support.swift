import Foundation
import MacPeekCore
import PortPeekKit

func fixture(_ name: String) throws -> String {
    guard let url = Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures") else {
        throw NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing \(name)"])
    }
    return try String(contentsOf: url, encoding: .utf8)
}

/// Answers each command by looking at its arguments, and records what it was asked to run.
final class RoutedRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [(String, [String])] = []
    private let handler: @Sendable ([String]) throws -> CommandOutput
    init(_ handler: @escaping @Sendable ([String]) throws -> CommandOutput) { self.handler = handler }
    var calls: [(String, [String])] { lock.lock(); defer { lock.unlock() }; return _calls }
    private func record(_ executable: String, _ arguments: [String]) {
        lock.lock(); defer { lock.unlock() }
        _calls.append((executable, arguments))
    }
    func run(_ executable: String, _ arguments: [String]) async throws -> CommandOutput {
        record(executable, arguments)
        return try handler(arguments)
    }
}

/// Hands out the given outputs one per call (the last repeats).
final class SequenceBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [CommandOutput]
    init(_ items: [CommandOutput]) { self.items = items }
    func next() -> CommandOutput {
        lock.lock(); defer { lock.unlock() }
        return items.count > 1 ? items.removeFirst() : items[0]
    }
}

func output(_ text: String) -> CommandOutput { CommandOutput(stdout: text, stderr: "", status: 0) }
func failure(_ stderr: String, status: Int32 = 1) -> CommandOutput { CommandOutput(stdout: "", stderr: stderr, status: status) }

struct FakePorts: PortDiscoveryProtocol {
    let result: Result<[PortInfo], Error>
    func discover() async throws -> [PortInfo] { try result.get() }
}
