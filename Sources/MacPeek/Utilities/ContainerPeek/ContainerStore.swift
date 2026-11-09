#if os(macOS)
import Foundation
import MacPeekCore
import ContainerPeekKit

/// Observable state for ContainerPeek. Lists containers and VMs while the screen is open (the engines' `stats` take a
/// second or two, so at most every five seconds), runs an action only after an inline confirmation, and reads a
/// container's logs only when asked. Logs are shown, never logged, and forgotten when the screen is left.
@MainActor
final class ContainerStore: ObservableObject {
    enum LogsState: Equatable {
        case loading
        case loaded(ContainerLogs)
        case failed(String)
    }

    @Published private(set) var snapshot: ContainerSnapshot?
    @Published private(set) var error: String?
    @Published private(set) var isLoading = false
    @Published private(set) var busyContainerID: String?
    @Published private(set) var banner: Banner?
    @Published private(set) var logs: [String: LogsState] = [:]
    @Published var expandedID: String?
    @Published var query = ""

    private let reader: ContainerReading
    private let controller: ContainerControlling
    private let settings: AppSettings
    private var pollTask: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?
    private var logTasks: [String: Task<Void, Never>] = [:]
    private var lastUsage: ProcessUsageSnapshot?
    private var lastRead: Date?
    private var readGeneration = 0

    init(reader: ContainerReading, controller: ContainerControlling, settings: AppSettings) {
        self.reader = reader
        self.controller = controller
        self.settings = settings
    }

    /// The launcher's one-line summary: container and VM lists only, never `stats`.
    func launcherSummary() async -> String? {
        guard let quick = try? await reader.quickSnapshot(), !Task.isCancelled else { return nil }
        return quick.summary
    }

    /// One full read, for the refresh button and polling.
    func refreshOnce() async {
        readGeneration += 1
        let generation = readGeneration
        if snapshot == nil { isLoading = true }
        defer { if generation == readGeneration { isLoading = false } }
        let now = Date()
        let interval = lastRead.map { now.timeIntervalSince($0) } ?? 0
        do {
            let (result, usage) = try await reader.snapshot(previous: lastUsage, interval: interval)
            guard !Task.isCancelled, generation == readGeneration else { return }
            snapshot = result
            lastUsage = usage
            lastRead = now
            error = nil
            if let id = expandedID, !result.allContainers.contains(where: { $0.id == id }) { expandedID = nil }
        } catch {
            if Task.isCancelled || generation != readGeneration { return }
            self.error = error.localizedDescription
            Log.containerPeek.error("read failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func startPolling() {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshOnce()
                let seconds = max(self.settings.refreshInterval, 5)
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
        }
    }

    /// Stops reading and forgets logs. An action already sent to the engine is left to finish (stopping a container
    /// half-way is not something to interrupt), but its result is not shown.
    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        for task in logTasks.values { task.cancel() }
        logTasks.removeAll()
        logs.removeAll()
        lastUsage = nil
        lastRead = nil
        isLoading = false
    }

    func visible(_ engine: ContainerEngineReport) -> [ContainerInfo] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let sorted = engine.containers.sorted { lhs, rhs in
            if lhs.state.isActive != rhs.state.isActive { return lhs.state.isActive }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        guard !q.isEmpty else { return sorted }
        return sorted.filter { c in
            c.name.lowercased().contains(q) || c.image.lowercased().contains(q) || (c.composeProject ?? "").lowercased().contains(q)
                || c.ports.contains { $0.hostPort.map(String.init) == q }
        }
    }

    func perform(_ action: ContainerAction, on container: ContainerInfo, engine: ContainerEngineKind) {
        guard actionTask == nil else { return }
        busyContainerID = container.id
        actionTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.controller.perform(action, on: container, engine: engine)
            self.busyContainerID = nil
            self.actionTask = nil
            Log.containerPeek.info("\(action.rawValue, privacy: .public): \(String(describing: result), privacy: .public)")
            self.show(Banner(kind: result.isSuccess ? .success : .error, text: result.message(action: action, name: container.name)))
            if self.pollTask != nil { await self.refreshOnce() }
        }
    }

    func loadLogs(of container: ContainerInfo, engine: ContainerEngineKind) {
        logTasks[container.id]?.cancel()
        logs[container.id] = .loading
        let id = container.id
        logTasks[id] = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.reader.logs(of: container, engine: engine, lines: 200)
                guard !Task.isCancelled else { return }
                self.logs[id] = .loaded(result)
            } catch {
                if Task.isCancelled { return }
                self.logs[id] = .failed(error.localizedDescription)
            }
            self.logTasks[id] = nil
        }
    }

    func hideLogs(of container: ContainerInfo) {
        logTasks[container.id]?.cancel()
        logTasks[container.id] = nil
        logs[container.id] = nil
    }

    private func show(_ banner: Banner) {
        self.banner = banner
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if !Task.isCancelled { self?.banner = nil }
        }
    }
}
#endif
