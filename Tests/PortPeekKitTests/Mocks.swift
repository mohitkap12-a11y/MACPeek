import Foundation
@testable import PortPeekKit
@testable import MacPeekCore

final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func get() -> T { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ v: T) { lock.lock(); value = v; lock.unlock() }
    func mutate(_ f: (inout T) -> Void) { lock.lock(); f(&value); lock.unlock() }
}

struct FakeRunner: CommandRunning {
    var output: CommandOutput
    var error: Error?
    func run(_ executable: String, _ arguments: [String]) async throws -> CommandOutput {
        if let error { throw error }
        return output
    }
}

/// Discovery whose results can change between calls.
final class ScriptedDiscovery: PortDiscoveryProtocol, @unchecked Sendable {
    private let box: LockedBox<[[PortInfo]]>
    let calls = LockedBox(0)
    var failure: Error?

    /// Each call returns the next snapshot; the last one repeats.
    init(_ snapshots: [[PortInfo]]) { box = LockedBox(snapshots) }

    func discover() async throws -> [PortInfo] {
        if let failure { throw failure }
        calls.mutate { $0 += 1 }
        var result: [PortInfo] = []
        box.mutate { snaps in
            result = snaps.first ?? []
            if snaps.count > 1 { snaps.removeFirst() }
        }
        return result
    }
}

final class FakeInspector: ProcessInspecting, @unchecked Sendable {
    let alive: LockedBox<Set<Int>>
    let starts: LockedBox<[Int: TimeInterval]>
    let signals = LockedBox<[(Int, Int32)]>([])
    var signalError: Int32 = 0
    /// If set, a successful signal removes the PID from `alive` (the process "exits").
    var diesOnSignal = true

    /// By default every live PID started at t=100 (matching `port(...)`'s default), so tests that
    /// are not about identity pass validation. Pass `starts: [:]` explicitly to model "unknown".
    init(alive: Set<Int>, starts: [Int: TimeInterval]? = nil) {
        self.alive = LockedBox(alive)
        self.starts = LockedBox(starts ?? Dictionary(uniqueKeysWithValues: alive.map { ($0, 100) }))
    }

    func isAlive(pid: Int) -> Bool { alive.get().contains(pid) }
    func startTime(pid: Int) -> TimeInterval? { starts.get()[pid] }
    func signal(pid: Int, signal: Int32) -> Int32 {
        signals.mutate { $0.append((pid, signal)) }
        if signalError != 0 { return signalError }
        if diesOnSignal { alive.mutate { $0.remove(pid) } }
        return 0
    }
}

func port(_ n: Int, pid: Int, name: String = "node", user: String? = "me", start: TimeInterval? = 100, address: String = "127.0.0.1") -> PortInfo {
    PortInfo(port: n, protocolType: .tcp, address: address, processName: name, pid: pid, user: user, state: .listen, startTime: start)
}
