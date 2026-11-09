import Foundation
import MacPeekCore

public protocol ContainerReading: Sendable {
    /// Containers of every installed engine, VMs of every installed manager, and the hypervisor processes running now.
    /// `previous` (the last reading's process counters) lets VM-process CPU be computed over the interval between reads.
    func snapshot(previous: ProcessUsageSnapshot?, interval: TimeInterval) async throws -> (ContainerSnapshot, ProcessUsageSnapshot?)
    /// The last `lines` lines a container printed. Read only on request; shown, never logged.
    func logs(of container: ContainerInfo, engine: ContainerEngineKind, lines: Int) async throws -> ContainerLogs
    /// Lists only, without resource use (for the launcher).
    func quickSnapshot() async throws -> ContainerSnapshot
}

public protocol ContainerControlling: Sendable {
    /// Re-reads the container, checks it is still the one the person saw and that the action applies, then runs it.
    func perform(_ action: ContainerAction, on container: ContainerInfo, engine: ContainerEngineKind) async -> ContainerActionResult
}

public extension ContainerReading {
    func snapshot() async throws -> ContainerSnapshot { try await snapshot(previous: nil, interval: 0).0 }
    /// For the launcher: lists only, without resource use. Readers that cannot do less read everything.
    func quickSnapshot() async throws -> ContainerSnapshot { try await snapshot() }
}

/// Where each tool is looked for. Fixed locations only (see `ExecutableLocator`): Docker Desktop, OrbStack, Rancher
/// Desktop and Colima all install or link a `docker` into one of them.
public struct ContainerToolLocators: Sendable {
    public var docker: ExecutableLocator
    public var podman: ExecutableLocator
    public var limactl: ExecutableLocator
    public var colima: ExecutableLocator
    public var tart: ExecutableLocator
    public var prlctl: ExecutableLocator

    public init(docker: ExecutableLocator, podman: ExecutableLocator, limactl: ExecutableLocator, colima: ExecutableLocator,
                tart: ExecutableLocator, prlctl: ExecutableLocator) {
        self.docker = docker
        self.podman = podman
        self.limactl = limactl
        self.colima = colima
        self.tart = tart
        self.prlctl = prlctl
    }

    public static let standard = ContainerToolLocators(
        docker: .standard("docker", extra: ["/Applications/Docker.app/Contents/Resources/bin/docker",
                                            "~/.orbstack/bin/docker", "~/.rd/bin/docker"]),
        podman: .standard("podman", extra: ["/opt/podman/bin/podman"]),
        limactl: .standard("limactl"),
        colima: .standard("colima"),
        tart: .standard("tart"),
        prlctl: .standard("prlctl", extra: ["/Applications/Parallels Desktop.app/Contents/MacOS/prlctl"]))

    func path(for engine: ContainerEngineKind) -> String? {
        switch engine {
        case .docker: return docker.locate()
        case .podman: return podman.locate()
        }
    }
}

/// Reads containers and VMs with each tool's own read-only list commands (fixed argument lists, never a shell), and
/// the hypervisor processes with the shared libproc reader. Every tool is optional: one that is missing is skipped,
/// one that fails is reported without hiding the others.
public struct SystemContainerReader: ContainerReading {
    private let runner: CommandRunning
    private let tools: ContainerToolLocators
    private let usage: ProcessUsageReading?

    public init(runner: CommandRunning = ShellCommand(timeout: 20), tools: ContainerToolLocators = .standard,
                usage: ProcessUsageReading? = nil) {
        self.runner = runner
        self.tools = tools
        self.usage = usage
    }

    public func snapshot(previous: ProcessUsageSnapshot?, interval: TimeInterval) async throws -> (ContainerSnapshot, ProcessUsageSnapshot?) {
        try await read(previous: previous, interval: interval, includeUsage: true)
    }

    /// Containers and VMs without `stats` or the process scan: cheap enough for the launcher.
    public func quickSnapshot() async throws -> ContainerSnapshot {
        try await read(previous: nil, interval: 0, includeUsage: false).0
    }

    private func read(previous: ProcessUsageSnapshot?, interval: TimeInterval, includeUsage: Bool) async throws
        -> (ContainerSnapshot, ProcessUsageSnapshot?) {
        var engines: [ContainerEngineReport] = []
        for kind in ContainerEngineKind.allCases {
            try Task.checkCancellation()
            guard let path = tools.path(for: kind) else { continue }
            engines.append(try await engineReport(kind, path: path, includeStats: includeUsage))
        }

        var vms: [VirtualMachine] = []
        var notes: [String] = []
        let managers: [(VMSource, ExecutableLocator, [String], (String) -> [VirtualMachine])] = [
            (.lima, tools.limactl, ["list", "--json"], VMListParser.lima),
            (.colima, tools.colima, ["list", "--json"], VMListParser.colima),
            (.tart, tools.tart, ["list", "--format", "json"], VMListParser.tart),
            (.parallels, tools.prlctl, ["list", "--all", "--json"], VMListParser.parallels),
        ]
        for (source, locator, arguments, parse) in managers {
            try Task.checkCancellation()
            guard let path = locator.locate() else { continue }
            guard let output = try await attempt(path, arguments) else {
                notes.append("\(source.displayName) did not answer.")
                continue
            }
            if output.status == 0 {
                vms.append(contentsOf: parse(output.stdout))
            } else {
                notes.append("\(source.displayName): \(Self.firstLine(output.stderr) ?? "exited with status \(output.status)")")
            }
        }

        var hosts: [VMHostProcess] = []
        var current: ProcessUsageSnapshot?
        if includeUsage, let usage {
            current = try? usage.read(isCancelled: { Task.isCancelled })
            if let current { hosts = VMHostSampling.hosts(current: current, previous: previous, interval: interval) }
        }
        return (ContainerSnapshot(engines: engines, virtualMachines: vms, vmProcesses: hosts, notes: notes), current)
    }

    private func engineReport(_ kind: ContainerEngineKind, path: String, includeStats: Bool) async throws -> ContainerEngineReport {
        let psArguments = kind == .docker ? ["ps", "--all", "--no-trunc", "--format", "{{json .}}"] : ["ps", "--all", "--format", "json"]
        var context: String?
        if kind == .docker, let output = try await attempt(path, ["context", "show"]), output.status == 0 {
            context = Self.firstLine(output.stdout)
        }
        guard let ps = try await attempt(path, psArguments) else {
            return ContainerEngineReport(kind: kind, executable: path, context: context,
                                         status: .failed("\(kind.displayName) did not answer in time."), containers: [], statsNote: nil)
        }
        guard ps.status == 0 else {
            return ContainerEngineReport(kind: kind, executable: path, context: context, status: Self.failureStatus(kind, ps),
                                         containers: [], statsNote: nil)
        }
        var containers = kind == .docker ? DockerPSParser.parse(ps.stdout) : PodmanPSParser.parse(ps.stdout)
        var statsNote: String?
        if includeStats, containers.contains(where: { $0.state.isActive }) {
            try Task.checkCancellation()
            let statsArguments = kind == .docker ? ["stats", "--no-stream", "--no-trunc", "--format", "{{json .}}"]
                                                 : ["stats", "--no-stream", "--format", "json"]
            if let stats = try await attempt(path, statsArguments), stats.status == 0 {
                let parsed = kind == .docker ? DockerStatsParser.parse(stats.stdout) : PodmanStatsParser.parse(stats.stdout)
                containers = ContainerStatsMerge.merge(containers, stats: parsed)
            } else {
                statsNote = "CPU and memory use could not be read."
            }
        }
        return ContainerEngineReport(kind: kind, executable: path, context: context, status: .running,
                                     containers: containers, statsNote: statsNote)
    }

    static func failureStatus(_ kind: ContainerEngineKind, _ output: CommandOutput) -> EngineStatus {
        let detail = firstLine(output.stderr) ?? "exited with status \(output.status)"
        let lower = output.stderr.lowercased()
        if lower.contains("cannot connect to the docker daemon") || lower.contains("is the docker daemon running")
            || lower.contains("cannot connect to podman") || lower.contains("connection refused")
            || lower.contains("no such file or directory") && lower.contains(".sock") {
            switch kind {
            case .docker: return .notRunning("The Docker engine is not running. Start Docker Desktop, OrbStack, Colima or Rancher Desktop.")
            case .podman: return .notRunning("No Podman machine is running. Start one with podman machine start.")
            }
        }
        return .failed(detail)
    }

    public func logs(of container: ContainerInfo, engine: ContainerEngineKind, lines: Int) async throws -> ContainerLogs {
        guard ContainerID.isValid(container.id) else { throw ContainerError.invalidID }
        guard let path = tools.path(for: engine) else { throw ContainerError.toolMissing(engine.displayName) }
        let count = min(max(lines, 1), 1000)
        let output = try await runner.run(path, ["logs", "--tail", String(count), container.id])
        guard output.status == 0 else {
            throw ContainerError.commandFailed(Self.firstLine(output.stderr) ?? "\(engine.displayName) exited with status \(output.status)")
        }
        // Containers print to stdout and stderr; `logs` replays both. They are shown together, stdout first.
        let out = output.stdout.hasSuffix("\n") ? String(output.stdout.dropLast()) : output.stdout
        let text = out + (output.stderr.isEmpty ? "" : (out.isEmpty ? "" : "\n") + output.stderr)
        var all = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if all.last == "" { all.removeLast() }
        return ContainerLogs(containerID: container.id, lines: Array(all.suffix(count)), truncated: all.count > count)
    }

    private func attempt(_ executable: String, _ arguments: [String]) async throws -> CommandOutput? {
        do { return try await runner.run(executable, arguments) }
        catch is CancellationError { throw CancellationError() }
        catch CommandError.cancelled { throw CommandError.cancelled }
        catch { return nil }
    }

    static func firstLine(_ text: String) -> String? {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
    }
}

public enum ContainerError: Error, Equatable, LocalizedError {
    case invalidID
    case toolMissing(String)
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidID: return "That is not a container ID."
        case .toolMissing(let name): return "\(name) is not installed in a location MacPeek checks."
        case .commandFailed(let detail): return detail
        }
    }
}

/// CPU for hypervisor processes from two libproc readings.
public enum VMHostSampling {
    public static func hosts(current: ProcessUsageSnapshot, previous: ProcessUsageSnapshot?, interval: TimeInterval) -> [VMHostProcess] {
        let before = Dictionary((previous?.usages ?? []).map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        return current.usages.compactMap { usage in
            guard let kind = VMHostProcessMatcher.kind(of: usage.name) else { return nil }
            var cpu: Double?
            if interval > 0, let old = before[usage.pid], old.generation == usage.generation,
               usage.cpuTimeNanoseconds >= old.cpuTimeNanoseconds {
                cpu = Double(usage.cpuTimeNanoseconds - old.cpuTimeNanoseconds) / (interval * 1_000_000_000) * 100
            }
            return VMHostProcess(pid: usage.pid, name: usage.name, kind: kind, cpuPercent: cpu,
                                 memoryFootprintBytes: usage.memoryFootprintBytes)
        }
        .sorted { $0.memoryFootprintBytes > $1.memoryFootprintBytes }
    }
}

/// Runs container actions through the engine's CLI: `docker start|stop|restart|pause|unpause|rm <full id>`. Before
/// acting it lists the container again by ID and refuses if it is gone, has a different name, or is in a state where
/// the action does not apply. `rm` is never forced and never removes volumes.
public struct SystemContainerController: ContainerControlling {
    private let runner: CommandRunning
    private let tools: ContainerToolLocators

    /// `docker stop` waits up to 10 s for the container to exit before Docker kills it, so actions get a longer limit.
    public init(runner: CommandRunning = ShellCommand(timeout: 60), tools: ContainerToolLocators = .standard) {
        self.runner = runner
        self.tools = tools
    }

    public func perform(_ action: ContainerAction, on container: ContainerInfo, engine: ContainerEngineKind) async -> ContainerActionResult {
        guard ContainerID.isValid(container.id) else { return .changed("that is not a container ID.") }
        guard let path = tools.path(for: engine) else { return .failed("\(engine.displayName) is not installed.") }
        let listArguments = engine == .docker
            ? ["ps", "--all", "--no-trunc", "--filter", "id=\(container.id)", "--format", "{{json .}}"]
            : ["ps", "--all", "--filter", "id=\(container.id)", "--format", "json"]
        do {
            let list = try await runner.run(path, listArguments)
            guard list.status == 0 else {
                return .failed(SystemContainerReader.firstLine(list.stderr) ?? "\(engine.displayName) could not list containers.")
            }
            let found = (engine == .docker ? DockerPSParser.parse(list.stdout) : PodmanPSParser.parse(list.stdout))
                .first { $0.id == container.id || $0.id.hasPrefix(container.id) || container.id.hasPrefix($0.id) }
            guard let current = found else { return .changed("\(container.name) no longer exists.") }
            guard current.name == container.name else { return .changed("the container is now called \(current.name).") }
            guard current.availableActions.contains(action) else {
                return .changed("\(container.name) is \(current.state.label.lowercased()), so it cannot be \(Self.pastTense(action)).")
            }
            let output = try await runner.run(path, [action.subcommand, current.id])
            guard output.status == 0 else {
                return .failed(SystemContainerReader.firstLine(output.stderr) ?? "\(engine.displayName) exited with status \(output.status)")
            }
            return .done
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static func pastTense(_ action: ContainerAction) -> String {
        switch action {
        case .start: return "started"
        case .stop: return "stopped"
        case .restart: return "restarted"
        case .pause: return "paused"
        case .unpause: return "resumed"
        case .remove: return "removed"
        }
    }
}
