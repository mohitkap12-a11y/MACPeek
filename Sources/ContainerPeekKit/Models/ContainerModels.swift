import Foundation
import MacPeekCore

/// A container engine MacPeek talks to through its own command-line tool.
public enum ContainerEngineKind: String, Codable, Sendable, CaseIterable {
    case docker
    case podman

    public var displayName: String {
        switch self {
        case .docker: return "Docker"
        case .podman: return "Podman"
        }
    }
}

/// One published port: `0.0.0.0:8080->80/tcp`, or an exposed but unpublished `5432/tcp` (no host port).
public struct PortMapping: Hashable, Codable, Sendable {
    public let hostIP: String?
    public let hostPort: Int?
    public let containerPort: Int
    /// Last port of a range (`8000-8010->8000-8010/tcp`), nil for a single port.
    public let containerPortEnd: Int?
    public let protocolName: String

    public init(hostIP: String?, hostPort: Int?, containerPort: Int, containerPortEnd: Int? = nil, protocolName: String) {
        self.hostIP = hostIP
        self.hostPort = hostPort
        self.containerPort = containerPort
        self.containerPortEnd = containerPortEnd
        self.protocolName = protocolName
    }

    public var isPublished: Bool { hostPort != nil }

    /// "localhost:8080 → 80/tcp", "5432/tcp (not published)".
    public var label: String {
        let inside = containerPortEnd.map { "\(containerPort)-\($0)" } ?? String(containerPort)
        guard let hostPort else { return "\(inside)/\(protocolName) (not published)" }
        let host: String
        switch hostIP {
        case nil, "", "0.0.0.0", "::", "[::]": host = "*"
        default: host = hostIP!.contains(":") ? "[\(hostIP!)]" : hostIP!
        }
        return "\(host):\(hostPort) → \(inside)/\(protocolName)"
    }
}

public enum ContainerState: Codable, Hashable, Sendable {
    case running, paused, restarting, created, exited, dead, removing
    case other(String)

    public init(raw: String) {
        switch raw.lowercased() {
        case "running", "up": self = .running
        case "paused": self = .paused
        case "restarting": self = .restarting
        case "created", "configured", "initialized": self = .created
        case "exited", "stopped": self = .exited
        case "dead": self = .dead
        case "removing": self = .removing
        default: self = .other(raw)
        }
    }

    /// Older Docker versions print no `State`, only `Status` ("Up 2 hours (Paused)", "Exited (0) 3 days ago").
    public init(status: String) {
        let lower = status.lowercased()
        if lower.hasPrefix("up") { self = lower.contains("(paused)") ? .paused : .running }
        else if lower.hasPrefix("exited") { self = .exited }
        else if lower.hasPrefix("created") { self = .created }
        else if lower.hasPrefix("restarting") { self = .restarting }
        else if lower.hasPrefix("dead") { self = .dead }
        else if lower.hasPrefix("removal") || lower.hasPrefix("removing") { self = .removing }
        else { self = .other(status) }
    }

    public var label: String {
        switch self {
        case .running: return "Running"
        case .paused: return "Paused"
        case .restarting: return "Restarting"
        case .created: return "Created"
        case .exited: return "Stopped"
        case .dead: return "Dead"
        case .removing: return "Removing"
        case .other(let raw): return raw
        }
    }

    public var isActive: Bool { self == .running || self == .restarting }
}

/// Resource use of one running container, as the engine reports it (`docker stats --no-stream`): a single reading.
public struct ContainerStats: Equatable, Codable, Sendable {
    /// Percent of one CPU core (can exceed 100 on several cores), as the engine computes it.
    public let cpuPercent: Double?
    public let memoryUsedBytes: UInt64?
    public let memoryLimitBytes: UInt64?
    public let memoryPercent: Double?
    public let pids: Int?

    public init(cpuPercent: Double?, memoryUsedBytes: UInt64?, memoryLimitBytes: UInt64?, memoryPercent: Double?, pids: Int?) {
        self.cpuPercent = cpuPercent
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryLimitBytes = memoryLimitBytes
        self.memoryPercent = memoryPercent
        self.pids = pids
    }
}

public struct ContainerInfo: Identifiable, Equatable, Codable, Sendable {
    /// The full container ID, as the engine prints it with `--no-trunc` (Podman stats use a 12-character prefix).
    public let id: String
    public let name: String
    public let image: String
    public let state: ContainerState
    /// The engine's own words: "Up 2 hours", "Exited (137) 3 days ago".
    public let status: String
    public let ports: [PortMapping]
    /// The Compose project and service, from the `com.docker.compose.*` labels.
    public let composeProject: String?
    public let composeService: String?
    public let createdAt: String?
    public var stats: ContainerStats?

    public init(id: String, name: String, image: String, state: ContainerState, status: String, ports: [PortMapping],
                composeProject: String?, composeService: String?, createdAt: String?, stats: ContainerStats? = nil) {
        self.id = id
        self.name = name
        self.image = image
        self.state = state
        self.status = status
        self.ports = ports
        self.composeProject = composeProject
        self.composeService = composeService
        self.createdAt = createdAt
        self.stats = stats
    }

    public var shortID: String { String(id.prefix(12)) }
    public var publishedPorts: [PortMapping] { ports.filter(\.isPublished) }

    /// The actions that make sense in the container's current state.
    public var availableActions: [ContainerAction] {
        switch state {
        case .running, .restarting: return [.stop, .restart, .pause]
        case .paused: return [.unpause, .stop]
        case .created, .exited, .dead: return [.start, .remove]
        case .removing, .other: return []
        }
    }
}

public enum EngineStatus: Equatable, Codable, Sendable {
    /// The engine answered.
    case running
    /// The tool is installed but its daemon or virtual machine is not running.
    case notRunning(String)
    /// The tool ran and failed for another reason.
    case failed(String)
}

public struct ContainerEngineReport: Identifiable, Equatable, Codable, Sendable {
    public var id: String { kind.rawValue }
    public let kind: ContainerEngineKind
    public let executable: String
    /// The Docker context in use (Docker Desktop, OrbStack, Colima and Rancher Desktop each add one), when known.
    public let context: String?
    public let status: EngineStatus
    public let containers: [ContainerInfo]
    /// Set when containers were listed but their resource use could not be read.
    public let statsNote: String?

    public init(kind: ContainerEngineKind, executable: String, context: String?, status: EngineStatus,
                containers: [ContainerInfo], statsNote: String?) {
        self.kind = kind
        self.executable = executable
        self.context = context
        self.status = status
        self.containers = containers
        self.statsNote = statsNote
    }

    public var runningCount: Int { containers.filter { $0.state.isActive }.count }
}

/// A virtual-machine manager MacPeek can list VMs from.
public enum VMSource: String, Codable, Sendable, CaseIterable {
    case lima, colima, tart, parallels

    public var displayName: String {
        switch self {
        case .lima: return "Lima"
        case .colima: return "Colima"
        case .tart: return "Tart"
        case .parallels: return "Parallels Desktop"
        }
    }
}

public struct VirtualMachine: Identifiable, Equatable, Codable, Sendable {
    public var id: String { "\(source.rawValue):\(name)" }
    public let source: VMSource
    public let name: String
    /// The manager's own word for the state ("Running", "stopped", "suspended").
    public let state: String
    public let isRunning: Bool
    public let cpus: Int?
    /// Memory assigned to the VM (its configured size, not what it uses right now).
    public let memoryBytes: UInt64?
    public let diskBytes: UInt64?
    /// Extra facts worth showing: VM type, architecture, runtime.
    public let detail: String?

    public init(source: VMSource, name: String, state: String, isRunning: Bool, cpus: Int?, memoryBytes: UInt64?,
                diskBytes: UInt64?, detail: String?) {
        self.source = source
        self.name = name
        self.state = state
        self.isRunning = isRunning
        self.cpus = cpus
        self.memoryBytes = memoryBytes
        self.diskBytes = diskBytes
        self.detail = detail
    }
}

/// A process on the Mac that hosts a virtual machine (Apple's Virtualization framework, QEMU, Parallels, VMware), with
/// what macOS counts for it. This is the real cost of a VM on the Mac, whichever tool started it.
public struct VMHostProcess: Identifiable, Equatable, Codable, Sendable {
    public var id: Int { pid }
    public let pid: Int
    public let name: String
    /// What kind of hypervisor process it is, in plain words.
    public let kind: String
    /// Percent of one core over the last sampling interval; nil until two readings exist.
    public let cpuPercent: Double?
    public let memoryFootprintBytes: UInt64

    public init(pid: Int, name: String, kind: String, cpuPercent: Double?, memoryFootprintBytes: UInt64) {
        self.pid = pid
        self.name = name
        self.kind = kind
        self.cpuPercent = cpuPercent
        self.memoryFootprintBytes = memoryFootprintBytes
    }
}

public struct ContainerSnapshot: Equatable, Codable, Sendable {
    public let engines: [ContainerEngineReport]
    public let virtualMachines: [VirtualMachine]
    public let vmProcesses: [VMHostProcess]
    /// VM managers whose list could not be read, with the reason.
    public let notes: [String]

    public init(engines: [ContainerEngineReport], virtualMachines: [VirtualMachine], vmProcesses: [VMHostProcess], notes: [String]) {
        self.engines = engines
        self.virtualMachines = virtualMachines
        self.vmProcesses = vmProcesses
        self.notes = notes
    }

    public var allContainers: [ContainerInfo] { engines.flatMap(\.containers) }
    public var runningContainers: Int { engines.reduce(0) { $0 + $1.runningCount } }
    public var runningVMs: Int { virtualMachines.filter(\.isRunning).count }
    public var nothingInstalled: Bool { engines.isEmpty && virtualMachines.isEmpty && vmProcesses.isEmpty && notes.isEmpty }

    /// "3 containers, 1 VM running" for the launcher.
    public var summary: String {
        let containers = runningContainers
        let vms = max(runningVMs, 0)
        if engines.isEmpty && virtualMachines.isEmpty && vmProcesses.isEmpty { return "No engines found" }
        var parts: [String] = []
        parts.append(containers == 1 ? "1 container" : "\(containers) containers")
        if vms > 0 || !virtualMachines.isEmpty { parts.append(vms == 1 ? "1 VM" : "\(vms) VMs") }
        return parts.joined(separator: ", ") + " running"
    }
}

/// What a person can do to a container from MacPeek. Each maps to one engine subcommand with a fixed argument list.
public enum ContainerAction: String, Codable, Sendable, CaseIterable {
    case start, stop, restart, pause, unpause, remove

    public var title: String {
        switch self {
        case .start: return "Start"
        case .stop: return "Stop"
        case .restart: return "Restart"
        case .pause: return "Pause"
        case .unpause: return "Resume"
        case .remove: return "Remove"
        }
    }

    /// `remove` deletes the container (never its volumes or image); stop and restart end its processes.
    public var needsConfirmation: Bool { self == .remove || self == .stop || self == .restart }

    var subcommand: String {
        switch self {
        case .remove: return "rm"
        default: return rawValue
        }
    }
}

public enum ContainerActionResult: Equatable, Codable, Sendable {
    case done
    /// The container is gone, renamed, or now in a state where the action does not apply: nothing was done.
    case changed(String)
    case failed(String)

    public var isSuccess: Bool { self == .done }

    public func message(action: ContainerAction, name: String) -> String {
        switch self {
        case .done:
            switch action {
            case .start: return "Started \(name)."
            case .stop: return "Stopped \(name)."
            case .restart: return "Restarted \(name)."
            case .pause: return "Paused \(name)."
            case .unpause: return "Resumed \(name)."
            case .remove: return "Removed \(name)."
            }
        case .changed(let reason): return "Nothing done: \(reason)"
        case .failed(let reason): return "\(action.title) failed: \(reason)"
        }
    }
}

/// The last lines a container printed, read only when the person asks.
public struct ContainerLogs: Equatable, Codable, Sendable {
    public let containerID: String
    public let lines: [String]
    public let truncated: Bool

    public init(containerID: String, lines: [String], truncated: Bool) {
        self.containerID = containerID
        self.lines = lines
        self.truncated = truncated
    }
}
