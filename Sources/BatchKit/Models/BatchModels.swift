import Foundation

/// One thing a batch installs. Version 1 installs only what needs no administrator password: Homebrew packages, Ollama
/// models and container images. Every name is checked by `BatchValidation` before any command is built.
public struct BatchItem: Equatable, Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// `brew install <name>`.
        case brewFormula
        /// `brew install --cask <name>`. A cask that needs an administrator password fails with an explanation.
        case brewCask
        /// A model pulled through the Mac's running Ollama (`POST /api/pull` on 127.0.0.1:11434).
        case ollamaModel
        /// `docker pull <reference>`.
        case containerImage
    }

    public let kind: Kind
    /// A Homebrew formula or cask, an Ollama model ("llama3.3:70b") or an image reference ("postgres:17").
    public let name: String
    /// Only for `brewFormula`: run `brew services start <name>` afterwards (e.g. Ollama, so its models can be pulled).
    public let startService: Bool
    /// What the console knows the item needs, from its catalog. Checked before anything downloads.
    public let requirements: BatchRequirements

    public init(kind: Kind, name: String, startService: Bool = false, requirements: BatchRequirements = .none) {
        self.kind = kind
        self.name = name
        self.startService = startService
        self.requirements = requirements
    }

    /// "Homebrew ollama", "Ollama model llama3.3:70b", "Image postgres:17".
    public var title: String {
        switch kind {
        case .brewFormula: return "Homebrew \(name)"
        case .brewCask: return "Homebrew cask \(name)"
        case .ollamaModel: return "Ollama model \(name)"
        case .containerImage: return "Image \(name)"
        }
    }
}

/// Memory and disk an item needs. Zero means "not known".
public struct BatchRequirements: Equatable, Hashable, Codable, Sendable {
    public let memoryBytes: UInt64
    public let diskBytes: UInt64

    public static let none = BatchRequirements(memoryBytes: 0, diskBytes: 0)

    public init(memoryBytes: UInt64 = 0, diskBytes: UInt64 = 0) {
        self.memoryBytes = memoryBytes
        self.diskBytes = diskBytes
    }
}

/// What a console asks a Mac to install, in order.
public struct BatchPlan: Equatable, Codable, Sendable {
    /// Chosen by the console; the same id on every Mac of one batch.
    public let id: String
    /// Shown to people, e.g. "AI Dev Box".
    public let name: String
    public let items: [BatchItem]

    public init(id: String = UUID().uuidString, name: String, items: [BatchItem]) {
        self.id = id
        self.name = name
        self.items = items
    }
}

/// The answer to a preflight, for one item.
public struct BatchItemCheck: Equatable, Codable, Sendable {
    public enum Verdict: String, Codable, Sendable {
        /// Will be installed.
        case ready
        /// Already on this Mac: skipped, nothing to do.
        case installed
        /// Cannot be installed here; `reason` says why.
        case blocked
    }

    public let item: BatchItem
    public let verdict: Verdict
    public let reason: String?

    public init(item: BatchItem, verdict: Verdict, reason: String? = nil) {
        self.item = item
        self.verdict = verdict
        self.reason = reason
    }
}

/// Where one item of a running batch is.
public struct BatchItemState: Equatable, Codable, Sendable {
    public enum Phase: String, Codable, Sendable {
        case queued, running, done, skipped, failed, cancelled
    }

    public let item: BatchItem
    public var phase: Phase
    /// 0...1 while running when the tool reports it (Ollama pulls do); nil when not known.
    public var progress: Double?
    /// Why it was skipped or failed, or what it is doing ("Downloading 12.4 of 43 GB").
    public var detail: String?

    public init(item: BatchItem, phase: Phase = .queued, progress: Double? = nil, detail: String? = nil) {
        self.item = item
        self.phase = phase
        self.progress = progress
        self.detail = detail
    }

    public var isFinished: Bool { [.done, .skipped, .failed, .cancelled].contains(phase) }
}

/// A batch on one Mac: answered by `batch.start`, `batch.status` and `batch.cancel`.
public struct BatchStatus: Equatable, Codable, Sendable {
    public enum Phase: String, Codable, Sendable {
        /// Waiting for an earlier batch on this Mac to finish.
        case queued
        case running
        /// Every item ended; see each item for how.
        case finished
        case cancelled
    }

    public let id: String
    public let name: String
    public var phase: Phase
    public var items: [BatchItemState]
    public let startedBy: String
    public let createdAt: Date
    public var finishedAt: Date?

    public init(plan: BatchPlan, startedBy: String, createdAt: Date) {
        id = plan.id
        name = plan.name
        phase = .queued
        items = plan.items.map { BatchItemState(item: $0) }
        self.startedBy = startedBy
        self.createdAt = createdAt
        finishedAt = nil
    }

    public func count(_ phase: BatchItemState.Phase) -> Int { items.filter { $0.phase == phase }.count }

    /// 0...1 over all items; a running item counts by its progress, or half when that is not known.
    public var progress: Double {
        guard !items.isEmpty else { return 1 }
        let sum = items.reduce(0.0) { total, state in
            total + (state.isFinished ? 1 : state.phase == .running ? (state.progress ?? 0.5) : 0)
        }
        return sum / Double(items.count)
    }
}
