import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import MacPeekCore
import GPUPeekKit

/// Asks a runner's own API on this Mac. Only `127.0.0.1` is ever contacted, with a short timeout and no proxy, so
/// nothing leaves the Mac.
public protocol LocalAPIFetching: Sendable {
    func get(port: Int, path: String) async throws -> Data
}

public enum LocalAPIError: Error, Equatable, LocalizedError {
    case badStatus(Int)
    case invalidPath

    public var errorDescription: String? {
        switch self {
        case .badStatus(let code): return "answered with HTTP \(code)"
        case .invalidPath: return "invalid path"
        }
    }
}

public struct LoopbackAPIClient: LocalAPIFetching {
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 2) {
        self.timeout = timeout
    }

    public func get(port: Int, path: String) async throws -> Data {
        guard path.hasPrefix("/"), !path.contains("@"), (1...65535).contains(port),
              let url = URL(string: "http://127.0.0.1:\(port)\(path)") else { throw LocalAPIError.invalidPath }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.connectionProxyDictionary = [:]
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response): (Data, URLResponse) = try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: request) { data, response, error in
                if let error { continuation.resume(throwing: error) }
                else if let data, let response { continuation.resume(returning: (data, response)) }
                else { continuation.resume(throwing: URLError(.badServerResponse)) }
            }.resume()
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw LocalAPIError.badStatus(http.statusCode) }
        return data
    }
}

/// What the previous reading counted, so CPU and GPU can be computed over the interval between two reads.
public struct ModelSamplingState: Sendable {
    public let usage: ProcessUsageSnapshot?
    public let gpuClients: [GPUClient]?
    public let date: Date

    public init(usage: ProcessUsageSnapshot?, gpuClients: [GPUClient]?, date: Date) {
        self.usage = usage
        self.gpuClients = gpuClients
        self.date = date
    }
}

public protocol ModelReading: Sendable {
    func snapshot(previous: ModelSamplingState?) async throws -> (ModelSnapshot, ModelSamplingState)
}

public extension ModelReading {
    func snapshot() async throws -> ModelSnapshot { try await snapshot(previous: nil).0 }
}

public enum ModelError: Error, Equatable, LocalizedError {
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let detail): return detail
        }
    }
}

/// Finds runner processes with `ps` (read-only), measures them with libproc and the GPU clients, and asks Ollama
/// (`127.0.0.1:11434/api/ps`) and LM Studio (`127.0.0.1:1234/api/v0/models`) which models they have loaded, only when
/// their processes are running. Models of MLX and llama.cpp come from their command line, the only place they say it.
public struct SystemModelReader: ModelReading {
    static let ps = "/bin/ps"
    public static let ollamaPort = 11434
    public static let lmStudioPort = 1234
    private let runner: CommandRunning
    private let api: LocalAPIFetching
    private let usage: ProcessUsageReading?
    private let gpu: GPUReading?

    public init(runner: CommandRunning = ShellCommand(timeout: 10), api: LocalAPIFetching = LoopbackAPIClient(),
                usage: ProcessUsageReading? = nil, gpu: GPUReading? = nil) {
        self.runner = runner
        self.api = api
        self.usage = usage
        self.gpu = gpu
    }

    public func snapshot(previous: ModelSamplingState?) async throws -> (ModelSnapshot, ModelSamplingState) {
        let comm = try await runner.run(Self.ps, ["-axo", "pid=,ppid=,comm="])
        guard comm.status == 0 else {
            let detail = comm.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ModelError.commandFailed(detail.isEmpty ? "ps exited with status \(comm.status)" : detail)
        }
        let args = try await runner.run(Self.ps, ["-axww", "-o", "pid=,args="])
        let lines = ProcessLineParser.parse(comm: comm.stdout, args: args.status == 0 ? args.stdout : "")

        var matched: [(ProcessLine, RunnerMatcher.Match)] = []
        for line in lines { if let match = RunnerMatcher.match(line) { matched.append((line, match)) } }

        let now = Date()
        var usageNow: ProcessUsageSnapshot?
        var clientsNow: [GPUClient]?
        if !matched.isEmpty {
            try Task.checkCancellation()
            usageNow = try? usage?.read(isCancelled: { Task.isCancelled })
            clientsNow = try? await gpu?.clients()
        }
        let interval = previous.map { now.timeIntervalSince($0.date) } ?? 0
        let usageByPID = Dictionary((usageNow?.usages ?? []).map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        let previousUsage = Dictionary((previous?.usage?.usages ?? []).map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        let gpuShares = Dictionary(GPUClientSampling.usage(current: clientsNow ?? [], previous: previous?.gpuClients, interval: interval)
            .map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })

        var runners: [LLMRunner] = []
        for kind in RunnerKind.allCases {
            let mine = matched.filter { $0.1.kind == kind }
            guard !mine.isEmpty else { continue }
            let processes = mine.map { line, match -> RunnerProcess in
                let current = usageByPID[line.pid]
                var cpu: Double?
                if let current, let old = previousUsage[line.pid], old.generation == current.generation, interval > 0,
                   current.cpuTimeNanoseconds >= old.cpuTimeNanoseconds {
                    cpu = Double(current.cpuTimeNanoseconds - old.cpuTimeNanoseconds) / (interval * 1_000_000_000) * 100
                }
                return RunnerProcess(pid: line.pid, name: line.name, role: match.role,
                                     memoryFootprintBytes: current?.memoryFootprintBytes, cpuPercent: cpu,
                                     gpuPercent: gpuShares[line.pid]?.gpuPercent)
            }
            var models: [LoadedModel] = []
            var note: String?
            switch kind {
            case .ollama:
                do { models = OllamaPSParser.parse(try await api.get(port: Self.ollamaPort, path: "/api/ps")) ?? [] }
                catch is CancellationError { throw CancellationError() }
                catch { note = "Ollama's API on port \(Self.ollamaPort) did not answer, so loaded models are not known." }
            case .lmStudio:
                do {
                    if let parsed = LMStudioModelsParser.parse(try await api.get(port: Self.lmStudioPort, path: "/api/v0/models")) {
                        models = parsed
                    } else { note = "LM Studio's server answered in a format MacPeek does not understand." }
                } catch is CancellationError { throw CancellationError() }
                catch { note = "LM Studio's local server is off, so loaded models are not known. Turn it on in LM Studio's Developer tab to see them." }
            case .mlx, .llamaCpp, .llamafile:
                var seen: Set<String> = []
                for (line, _) in mine {
                    if let model = RunnerMatcher.modelArgument(line), seen.insert(model).inserted {
                        models.append(LoadedModel(name: model, source: .commandLine))
                    }
                }
                if models.isEmpty { note = "The model is not named on the command line." }
            }
            runners.append(LLMRunner(kind: kind, processes: processes.sorted { ($0.memoryFootprintBytes ?? 0) > ($1.memoryFootprintBytes ?? 0) },
                                     models: models, note: note))
        }
        return (ModelSnapshot(runners: runners), ModelSamplingState(usage: usageNow, gpuClients: clientsNow, date: now))
    }
}
