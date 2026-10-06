#if os(macOS)
import Foundation
import MacPeekCore
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
    @Published private(set) var killingPID: Int?
    /// Set when SIGTERM did not stop the process: the UI then offers an explicit force kill of exactly this process.
    @Published private(set) var forceCandidate: ProcessEntry?
    @Published private(set) var banner: Banner?

    private let lister: ProcessListing
    private let terminator: ProcessTerminator
    private let permissions: PermissionService
    private let settings: AppSettings
    private let notifier: NotificationService
    private let currentUID = Int(getuid())
    private var task: Task<Void, Never>?
    private var detailsTask: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?
    private var terminationTask: Task<Void, Never>?
    /// True only while the ProcessPeek screen is on screen: nothing reads the process table in the background.
    private var isActive = false

    init(lister: ProcessListing, terminator: ProcessTerminator, permissions: PermissionService,
         settings: AppSettings, notifier: NotificationService) {
        self.lister = lister
        self.terminator = terminator
        self.permissions = permissions
        self.settings = settings
        self.notifier = notifier
    }

    func setActive(_ active: Bool) { isActive = active }

    func capability(for entry: ProcessEntry) -> TerminationCapability { permissions.capability(for: entry) }

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
        forceCandidate = nil
        banner = nil
        bannerTask?.cancel()
        terminationTask?.cancel()
        terminationTask = nil
        killingPID = nil
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
            // A force-kill offer is only valid for the exact process that ignored SIGTERM.
            if let candidate = forceCandidate, !Self.isSameProcess(result.entry(pid: candidate.pid), candidate) {
                forceCandidate = nil
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

    // MARK: Termination

    /// Termination runs in a store-owned task so leaving the screen cancels it (see `cancel()`).
    func terminate(_ entry: ProcessEntry) { start(entry, force: false) }
    func dismissForce() { forceCandidate = nil }

    /// Force-kills the *original* candidate (never a refreshed row that merely shares its PID); the termination
    /// service revalidates its identity again before sending SIGKILL.
    func confirmForceTerminate() {
        guard let candidate = forceCandidate else { return }
        start(candidate, force: true)
    }

    private func start(_ entry: ProcessEntry, force: Bool) {
        guard terminationTask == nil else { return }
        terminationTask = Task { [weak self] in
            await self?.run(entry, force: force)
            self?.terminationTask = nil
        }
    }

    private static func isSameProcess(_ current: ProcessEntry?, _ candidate: ProcessEntry) -> Bool {
        guard let current, let a = current.identityStartTime, let b = candidate.identityStartTime else { return false }
        return current.pid == candidate.pid && abs(a - b) <= 1
    }

    private func run(_ entry: ProcessEntry, force: Bool) async {
        killingPID = entry.pid
        forceCandidate = nil
        let result = force ? await terminator.forceTerminate(entry) : await terminator.terminate(entry)
        killingPID = nil
        // Left the screen mid-wait: no banner, force offer or notification for work the user walked away from.
        guard !Task.isCancelled else { return }
        Log.processPeek.info("pid \(entry.pid): \(String(describing: result), privacy: .public)")

        switch result {
        case .stillRunning where !force:
            // The graceful request was ignored: offer the explicit force kill.
            forceCandidate = entry
            show(Banner(kind: .error, text: result.message(for: entry)))
        case .stillRunning:
            // Even SIGKILL did not end it (rare: blocked in the kernel). Do not offer the same thing again.
            show(Banner(kind: .error, text: "\(entry.name) (PID \(entry.pid)) is still running even after a force kill. It may be stuck in the kernel; try again in a moment."))
        case .terminated:
            show(Banner(kind: .success, text: result.message(for: entry)))
            if settings.showNotifications {
                notifier.notify(title: "Terminated \(entry.name)", body: "\(entry.name) (PID \(entry.pid)) was terminated.")
            }
        default:
            show(Banner(kind: result.isSuccess ? .success : .error, text: result.message(for: entry)))
        }
        // Only while the screen is open: nothing reads the process table in the background.
        if isActive { refresh() }
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
