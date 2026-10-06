import Foundation
import MacPeekCore
@testable import FileLockPeekKit

func fixture(_ name: String) throws -> String {
    guard let url = Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures") else {
        throw NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing \(name)"])
    }
    return try String(contentsOf: url, encoding: .utf8)
}

final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func get() -> T { lock.lock(); defer { lock.unlock() }; return value }
    func mutate(_ f: (inout T) -> Void) { lock.lock(); f(&value); lock.unlock() }
}

/// Records every command it is asked to run and returns a canned result.
final class RecordingRunner: CommandRunning, @unchecked Sendable {
    let calls = LockedBox<[(String, [String])]>([])
    var output: CommandOutput
    var error: Error?
    init(output: CommandOutput = CommandOutput(stdout: "", stderr: "", status: 1)) { self.output = output }
    func run(_ executable: String, _ arguments: [String]) async throws -> CommandOutput {
        calls.mutate { $0.append((executable, arguments)) }
        if let error { throw error }
        return output
    }
}

enum DiscoveryStep {
    case holders([FileLockHolder])
    case fail(Error)
}

/// Discovery whose results change between calls (the last step repeats).
final class ScriptedFileDiscovery: FileLockDiscoveryProtocol, @unchecked Sendable {
    private let box: LockedBox<[DiscoveryStep]>
    let calls = LockedBox(0)
    var failure: Error?
    init(_ snapshots: [[FileLockHolder]]) { box = LockedBox(snapshots.map { .holders($0) }) }
    init(steps: [DiscoveryStep]) { box = LockedBox(steps) }
    func scan(path: String) async throws -> FileLockScan {
        if let failure { throw failure }
        calls.mutate { $0 += 1 }
        var step: DiscoveryStep = .holders([])
        box.mutate { steps in
            step = steps.first ?? .holders([])
            if steps.count > 1 { steps.removeFirst() }
        }
        switch step {
        case .holders(let holders): return FileLockScan(holders: holders)
        case .fail(let error): throw error
        }
    }
}

final class FakeInspector: ProcessInspecting, @unchecked Sendable {
    let alive: LockedBox<Set<Int>>
    let starts: [Int: TimeInterval]
    let signals = LockedBox<[Int32]>([])
    var signalError: Int32 = 0
    var diesOnSignal = true
    /// By default every live PID started at t=100, matching `holder(...)`'s default start time.
    init(alive: Set<Int>, starts: [Int: TimeInterval]? = nil) {
        self.alive = LockedBox(alive)
        self.starts = starts ?? Dictionary(uniqueKeysWithValues: alive.map { ($0, 100) })
    }
    func isAlive(pid: Int) -> Bool { alive.get().contains(pid) }
    func startTime(pid: Int) -> TimeInterval? { starts[pid] }
    func signal(pid: Int, signal: Int32) -> Int32 {
        signals.mutate { $0.append(signal) }
        if signalError != 0 { return signalError }
        if diesOnSignal { alive.mutate { $0.remove(pid) } }
        return 0
    }
}

func holder(_ pid: Int, name: String = "Docker", user: String? = "me", start: TimeInterval? = 100) -> FileLockHolder {
    FileLockHolder(pid: pid, processName: name, user: user,
                   files: [OpenFile(path: "/Users/me/data.db", descriptor: "3u", kind: .open(.readWrite))], startTime: start)
}
