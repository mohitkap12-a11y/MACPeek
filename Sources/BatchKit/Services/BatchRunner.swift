import Foundation

/// Runs batches on this Mac one at a time, in the order they arrive, and keeps the last few so consoles can follow them
/// (`batch.status`). Starting the same batch id twice returns the one already known, so a console can safely retry.
public actor BatchRunner {
    /// Writes one line to the Mac's activity log: what was installed for whom, and how it ended.
    public typealias Log = @Sendable (_ event: String, _ outcome: String) async -> Void

    public static let keptBatches = 20

    private let installer: BatchInstalling
    private let clock: @Sendable () -> Date
    private var batches: [BatchStatus] = []
    private var plans: [String: (plan: BatchPlan, log: Log)] = [:]
    private var queue: [String] = []
    private var worker: Task<Void, Never>?
    private var cancelled: Set<String> = []

    public init(installer: BatchInstalling = SystemBatchInstaller(), clock: @escaping @Sendable () -> Date = { Date() }) {
        self.installer = installer
        self.clock = clock
    }

    /// Queues a checked plan. The caller has validated it (`BatchValidation`) and the console's permission.
    @discardableResult
    public func start(_ plan: BatchPlan, by actor: String, log: @escaping Log) -> BatchStatus {
        if let known = batches.first(where: { $0.id == plan.id }) { return known }
        let status = BatchStatus(plan: plan, startedBy: actor, createdAt: clock())
        batches.insert(status, at: 0)
        plans[plan.id] = (plan, log)
        queue.append(plan.id)
        trim()
        if worker == nil {
            worker = Task { await self.drain() }
        }
        return status
    }

    /// Whether each item of a plan can be installed here now. Installs nothing.
    public func check(_ plan: BatchPlan) async -> [BatchItemCheck] {
        await installer.check(plan.items)
    }

    /// The batch with this id, or every batch kept, newest first.
    public func status(id: String? = nil) -> [BatchStatus] {
        guard let id else { return batches }
        return batches.filter { $0.id == id }
    }

    /// Stops a batch: the item running now is stopped, the rest are not started.
    public func cancel(id: String) -> BatchStatus? {
        guard let index = batches.firstIndex(where: { $0.id == id }) else { return nil }
        guard batches[index].phase == .queued || batches[index].phase == .running else { return batches[index] }
        cancelled.insert(id)
        if batches[index].phase == .queued {
            queue.removeAll { $0 == id }
            finish(index: index, phase: .cancelled)
        } else {
            current?.cancel()
        }
        return batches[index]
    }

    /// Waits until nothing is queued or running (for tests and for quitting cleanly).
    public func idle() async {
        while let worker { await worker.value }
    }

    // MARK: Running

    private var current: Task<BatchInstallResult, Never>?

    private func drain() async {
        while !queue.isEmpty {
            let id = queue.removeFirst()
            await run(id)
        }
        worker = nil
    }

    private func run(_ id: String) async {
        guard let (plan, log) = plans[id], index(of: id) != nil else { return }
        update(id) { $0.phase = .running }
        for (position, item) in plan.items.enumerated() {
            if cancelled.contains(id) {
                update(id) { status in
                    for i in position..<status.items.count where !status.items[i].isFinished { status.items[i].phase = .cancelled }
                }
                break
            }
            // Checked right before it runs: earlier items may have used disk space or installed what this needs.
            let check = await installer.recheck(item)
            switch check.verdict {
            case .installed:
                setItem(id, position, .skipped, detail: "Already installed")
                continue
            case .blocked:
                setItem(id, position, .skipped, detail: check.reason)
                await log("Install \(item.title) (batch “\(plan.name)”)", "Skipped: \(check.reason ?? "not possible on this Mac")")
                continue
            case .ready:
                break
            }
            setItem(id, position, .running, detail: nil)
            let installer = self.installer
            let task = Task { () -> BatchInstallResult in
                await installer.install(item) { [weak self] fraction, detail in
                    await self?.progress(id, position, fraction, detail)
                }
            }
            current = task
            let result = await task.value
            current = nil
            switch result {
            case .done:
                setItem(id, position, .done, detail: nil, progress: 1)
                await log("Install \(item.title) (batch “\(plan.name)”)", "Done")
            case .failed(let reason):
                let phase: BatchItemState.Phase = cancelled.contains(id) ? .cancelled : .failed
                setItem(id, position, phase, detail: reason)
                await log("Install \(item.title) (batch “\(plan.name)”)", phase == .cancelled ? "Cancelled" : "Failed: \(reason)")
            }
        }
        if let index = index(of: id) { finish(index: index, phase: cancelled.contains(id) ? .cancelled : .finished) }
        plans[id] = nil
        cancelled.remove(id)
    }

    private func progress(_ id: String, _ position: Int, _ fraction: Double?, _ detail: String?) {
        update(id) { status in
            guard position < status.items.count, status.items[position].phase == .running else { return }
            if let fraction { status.items[position].progress = fraction }
            if let detail { status.items[position].detail = detail }
        }
    }

    private func setItem(_ id: String, _ position: Int, _ phase: BatchItemState.Phase, detail: String?, progress: Double? = nil) {
        update(id) { status in
            guard position < status.items.count else { return }
            status.items[position].phase = phase
            status.items[position].detail = detail
            if let progress { status.items[position].progress = progress }
        }
    }

    private func finish(index: Int, phase: BatchStatus.Phase) {
        batches[index].phase = phase
        batches[index].finishedAt = clock()
        if phase == .cancelled {
            for i in batches[index].items.indices where !batches[index].items[i].isFinished { batches[index].items[i].phase = .cancelled }
        }
    }

    private func index(of id: String) -> Int? { batches.firstIndex { $0.id == id } }

    private func update(_ id: String, _ change: (inout BatchStatus) -> Void) {
        guard let index = index(of: id) else { return }
        change(&batches[index])
    }

    /// Keeps the newest batches, never dropping one that is queued or running.
    private func trim() {
        while batches.count > Self.keptBatches, let last = batches.lastIndex(where: { $0.phase == .finished || $0.phase == .cancelled }) {
            batches.remove(at: last)
        }
    }
}
