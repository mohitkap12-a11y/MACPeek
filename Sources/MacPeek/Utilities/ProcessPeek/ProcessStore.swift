#if os(macOS)
import Foundation
import ProcessPeekKit

/// Observable state for ProcessPeek. Reads the process table when the screen opens or the user asks (no polling),
/// and loads the command line and listening ports only for the process the user opens.
@MainActor
final class ProcessStore: ObservableObject {
    @Published private(set) var snapshot: ProcessSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published var query = ""
    @Published var showAllUsers = false
    @Published var sort: ProcessSort = .name
    @Published private(set) var selectedPID: Int?
    @Published private(set) var details: ProcessDetails?
    @Published private(set) var detailsLoading = false
    /// Set when a jump was requested to a PID, so the list can scroll to it.
    @Published private(set) var scrollTarget: Int?

    private let lister: ProcessListing
    private let currentUID = Int(getuid())
    private var task: Task<Void, Never>?
    private var detailsTask: Task<Void, Never>?

    init(lister: ProcessListing) {
        self.lister = lister
    }

    var visible: [ProcessEntry] {
        guard let snapshot else { return [] }
        return ProcessSearch.filter(snapshot.entries, query: query, ownedBy: showAllUsers ? nil : currentUID, sort: sort)
    }

    func isOwned(_ entry: ProcessEntry) -> Bool { entry.isOwned(by: currentUID) }

    // MARK: Loading

    func refresh() {
        task?.cancel()
        task = Task { [weak self] in await self?.load() }
    }

    /// Called when the screen is left: stop any read and forget the opened process, so a command line (which can
    /// contain secrets) does not stay in memory and nothing is left half-loaded on return.
    func cancel() {
        task?.cancel()
        task = nil
        isLoading = false
        select(nil)
    }

    private func load() async {
        isLoading = true
        defer { if !Task.isCancelled { isLoading = false } }
        do {
            let result = try await lister.snapshot()
            guard !Task.isCancelled else { return }
            let previous = selectedPID.flatMap { snapshot?.entry(pid: $0) }
            snapshot = result
            error = nil
            // Close the opened process if it exited, or if its PID now belongs to a different process.
            if let pid = selectedPID {
                let current = result.entry(pid: pid)
                if current == nil || (previous != nil && !PSProcessLister.sameProcess(previous?.startTime, current?.startTime)) {
                    select(nil)
                }
            }
        } catch {
            if Task.isCancelled { return }
            self.error = error.localizedDescription
            Log.processPeek.error("read failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Selection

    func toggle(_ pid: Int) { select(selectedPID == pid ? nil : pid) }

    func select(_ pid: Int?) {
        detailsTask?.cancel()
        selectedPID = pid
        details = nil
        detailsLoading = false
        guard let pid, let entry = snapshot?.entry(pid: pid) else { return }
        detailsLoading = true
        detailsTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.lister.details(for: entry)
                guard !Task.isCancelled else { return }
                self.details = result
            } catch {
                if Task.isCancelled { return }
                Log.processPeek.error("details failed: \(error.localizedDescription, privacy: .public)")
                self.details = ProcessDetails(pid: pid, commandLine: nil, listeningPorts: [], portsNote: error.localizedDescription)
            }
            self.detailsLoading = false
        }
    }

    /// Opens another process (a parent or child): clears the search and widens to all users if needed.
    func jump(to pid: Int) {
        guard let entry = snapshot?.entry(pid: pid) else { return }
        query = ""
        if !isOwned(entry) { showAllUsers = true }
        select(pid)
        scrollTarget = pid
    }

    func scrolled() { scrollTarget = nil }
}
#endif
