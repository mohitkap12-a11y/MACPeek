import Foundation

/// One entry of `pmset -g assertions` → "Listed by owning process".
public struct SleepAssertion: Identifiable, Equatable, Sendable {
    public let id: String
    public let pid: Int
    public let processName: String
    public let type: String
    public let name: String
    /// How long macOS says the assertion has been held ("01:01:14").
    public let heldFor: String
    /// Extra lines macOS printed under the assertion (for example a timeout).
    public let details: [String]

    public init(id: String, pid: Int, processName: String, type: String, name: String, heldFor: String, details: [String] = []) {
        self.id = id
        self.pid = pid
        self.processName = processName
        self.type = type
        self.name = name
        self.heldFor = heldFor
        self.details = details
    }

    /// Holds the whole system awake (as opposed to only the display, or nothing at all).
    public var preventsSystemSleep: Bool { SleepAssertionTypes.system.contains(type) }
    public var preventsDisplaySleep: Bool { SleepAssertionTypes.display.contains(type) }
    public var blocksSleep: Bool { preventsSystemSleep || preventsDisplaySleep }
}

public enum SleepAssertionTypes {
    public static let system: Set<String> = ["PreventUserIdleSystemSleep", "PreventSystemSleep", "NoIdleSleepAssertion"]
    public static let display: Set<String> = ["PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion"]
}

/// An entry under "Kernel Assertions" (USB devices, magic-wake network interfaces…).
public struct KernelAssertion: Identifiable, Equatable, Sendable {
    public let id: Int
    public let description: String
    public let owner: String

    public init(id: Int, description: String, owner: String) {
        self.id = id
        self.description = description
        self.owner = owner
    }
}

public struct AssertionReport: Equatable, Sendable {
    /// The system-wide counters in the order macOS printed them.
    public let systemStatus: [(name: String, count: Int)]
    public let assertions: [SleepAssertion]
    public let kernelAssertions: [KernelAssertion]

    public init(systemStatus: [(name: String, count: Int)], assertions: [SleepAssertion], kernelAssertions: [KernelAssertion]) {
        self.systemStatus = systemStatus
        self.assertions = assertions
        self.kernelAssertions = kernelAssertions
    }

    public static func == (lhs: AssertionReport, rhs: AssertionReport) -> Bool {
        lhs.assertions == rhs.assertions && lhs.kernelAssertions == rhs.kernelAssertions
            && lhs.systemStatus.map(\.name) == rhs.systemStatus.map(\.name)
            && lhs.systemStatus.map(\.count) == rhs.systemStatus.map(\.count)
    }

    public func count(_ name: String) -> Int { systemStatus.first { $0.name == name }?.count ?? 0 }
}

/// `pmset -g`: current settings plus macOS's own statement of what is preventing sleep.
public struct PowerSettings: Equatable, Sendable {
    public let values: [String: Int]
    /// Setting name → the processes macOS says are preventing it ("sleep" → ["bluetoothd", "powerd"]).
    public let preventedBy: [String: [String]]

    public init(values: [String: Int], preventedBy: [String: [String]]) {
        self.values = values
        self.preventedBy = preventedBy
    }

    public var sleepMinutes: Int? { values["sleep"] }
    public var displaySleepMinutes: Int? { values["displaysleep"] }
}

public struct SleepEvent: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable {
        case sleep = "Sleep"
        case wake = "Wake"
        /// A wake that does not light the display (maintenance, network, Power Nap).
        case darkWake = "DarkWake"
    }

    public let id: String
    public let date: Date
    public let kind: Kind
    /// The "due to …" text exactly as macOS logged it, without interpretation.
    public let reason: String?
    /// "AC", "Batt" or nil.
    public let powerSource: String?
    public let raw: String

    public init(date: Date, kind: Kind, reason: String?, powerSource: String?, raw: String, index: Int) {
        self.id = "\(Int(date.timeIntervalSince1970))-\(kind.rawValue)-\(index)"
        self.date = date
        self.kind = kind
        self.reason = reason
        self.powerSource = powerSource
        self.raw = raw
    }
}

/// A process's request that macOS wake the Mac at a given time.
public struct WakeRequest: Identifiable, Equatable, Sendable {
    public let id: String
    public let process: String
    public let request: String
    public let wakeAt: Date?
    public let info: String

    public init(process: String, request: String, wakeAt: Date?, info: String, index: Int) {
        self.id = "\(index)-\(process)-\(request)"
        self.process = process
        self.request = request
        self.wakeAt = wakeAt
        self.info = info
    }
}

public struct SleepHistory: Equatable, Sendable {
    /// Newest first.
    public let events: [SleepEvent]
    /// The most recent "Wake Requests" entry in the log, and when it was recorded.
    public let wakeRequests: [WakeRequest]
    public let wakeRequestsRecordedAt: Date?

    public init(events: [SleepEvent], wakeRequests: [WakeRequest], wakeRequestsRecordedAt: Date?) {
        self.events = events
        self.wakeRequests = wakeRequests
        self.wakeRequestsRecordedAt = wakeRequestsRecordedAt
    }

    public func count(of kind: SleepEvent.Kind) -> Int { events.filter { $0.kind == kind }.count }
}
