import Foundation
import MacPeekCore

/// A local LLM runner MacPeek recognises.
public enum RunnerKind: String, Codable, Sendable, CaseIterable {
    case ollama
    case lmStudio
    case mlx
    case llamaCpp
    case llamafile

    public var displayName: String {
        switch self {
        case .ollama: return "Ollama"
        case .lmStudio: return "LM Studio"
        case .mlx: return "MLX"
        case .llamaCpp: return "llama.cpp"
        case .llamafile: return "llamafile"
        }
    }
}

/// Where a model name came from: the runner's own local API (authoritative), or the command line it was started with.
public enum ModelSource: String, Codable, Sendable {
    case api
    case commandLine
}

public struct LoadedModel: Identifiable, Equatable, Codable, Sendable {
    public var id: String { name }
    public let name: String
    /// Memory the model takes, as the runner reports it.
    public let sizeBytes: UInt64?
    /// The part of it held for the GPU (Ollama's `size_vram`). On Apple silicon this is unified memory.
    public let gpuBytes: UInt64?
    public let contextLength: Int?
    public let quantization: String?
    public let parameterSize: String?
    public let family: String?
    /// When the runner will unload it if unused (Ollama's `expires_at`, as printed).
    public let expiresAt: String?
    public let source: ModelSource

    public init(name: String, sizeBytes: UInt64? = nil, gpuBytes: UInt64? = nil, contextLength: Int? = nil,
                quantization: String? = nil, parameterSize: String? = nil, family: String? = nil, expiresAt: String? = nil,
                source: ModelSource) {
        self.name = name
        self.sizeBytes = sizeBytes
        self.gpuBytes = gpuBytes
        self.contextLength = contextLength
        self.quantization = quantization
        self.parameterSize = parameterSize
        self.family = family
        self.expiresAt = expiresAt
        self.source = source
    }

    /// "100% GPU", "48% GPU / 52% CPU", "100% CPU": how Ollama splits a model, from its own numbers.
    public var processorSplit: String? {
        guard let size = sizeBytes, size > 0, let gpu = gpuBytes else { return nil }
        let share = Int((Double(min(gpu, size)) / Double(size) * 100).rounded())
        switch share {
        case 100: return "100% GPU"
        case 0: return "100% CPU"
        default: return "\(share)% GPU / \(100 - share)% CPU"
        }
    }
}

/// One process that belongs to a runner, with what macOS counts for it.
public struct RunnerProcess: Identifiable, Equatable, Codable, Sendable {
    public var id: Int { pid }
    public let pid: Int
    public let name: String
    /// "server", "model runner", "app"…
    public let role: String
    public let memoryFootprintBytes: UInt64?
    public let cpuPercent: Double?
    public let gpuPercent: Double?

    public init(pid: Int, name: String, role: String, memoryFootprintBytes: UInt64?, cpuPercent: Double?, gpuPercent: Double?) {
        self.pid = pid
        self.name = name
        self.role = role
        self.memoryFootprintBytes = memoryFootprintBytes
        self.cpuPercent = cpuPercent
        self.gpuPercent = gpuPercent
    }
}

public struct LLMRunner: Identifiable, Equatable, Codable, Sendable {
    public var id: String { kind.rawValue }
    public let kind: RunnerKind
    public let processes: [RunnerProcess]
    public let models: [LoadedModel]
    /// Why the model list is incomplete (an API that did not answer, a runner that does not say).
    public let note: String?

    public init(kind: RunnerKind, processes: [RunnerProcess], models: [LoadedModel], note: String?) {
        self.kind = kind
        self.processes = processes
        self.models = models
        self.note = note
    }

    /// Memory of all the runner's processes. Model weights mapped from disk are part of it once loaded.
    public var memoryFootprintBytes: UInt64? {
        let values = processes.compactMap(\.memoryFootprintBytes)
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    public var cpuPercent: Double? {
        let values = processes.compactMap(\.cpuPercent)
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    public var gpuPercent: Double? {
        let values = processes.compactMap(\.gpuPercent)
        return values.isEmpty ? nil : min(values.reduce(0, +), 100)
    }
}

public struct ModelSnapshot: Equatable, Codable, Sendable {
    public let runners: [LLMRunner]

    public init(runners: [LLMRunner]) {
        self.runners = runners
    }

    public var loadedModelCount: Int { runners.reduce(0) { $0 + $1.models.count } }

    public var summary: String {
        guard !runners.isEmpty else { return "No runners" }
        let models = loadedModelCount
        if models > 0 { return models == 1 ? "1 model loaded" : "\(models) models loaded" }
        return runners.count == 1 ? "\(runners[0].kind.displayName) running" : "\(runners.count) runners"
    }
}
