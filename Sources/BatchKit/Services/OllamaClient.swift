import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The Mac's own Ollama, through its API on `127.0.0.1:11434` only (no proxy), so nothing but Ollama's own download
/// leaves the Mac.
public protocol OllamaControlling: Sendable {
    /// Whether Ollama answers right now.
    func isRunning() async -> Bool
    /// The models it has, as `name:tag` ("llama3.3:70b"; a model pulled without a tag is "name:latest").
    func installedModels() async throws -> Set<String>
    /// Pulls one model, reporting progress (0...1 when Ollama says how much) and what it is doing.
    func pull(_ model: String, progress: @escaping @Sendable (Double?, String) async -> Void) async throws
}

public enum OllamaError: Error, Equatable, LocalizedError {
    case notRunning
    case refused(String)
    case badAnswer

    public var errorDescription: String? {
        switch self {
        case .notRunning: return "Ollama isn't running on this Mac."
        case .refused(let message): return message
        case .badAnswer: return "Ollama's answer could not be understood."
        }
    }
}

public enum OllamaNames {
    /// "llama3.3" → "llama3.3:latest"; a name with a tag is kept.
    public static func normalized(_ name: String) -> String {
        let last = name.split(separator: "/").last.map(String.init) ?? name
        return last.contains(":") ? name : name + ":latest"
    }

    /// Model names in `GET /api/tags`.
    static func parseTags(_ data: Data) -> Set<String>? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = object["models"] as? [[String: Any]] else { return nil }
        return Set(models.compactMap { ($0["name"] as? String) ?? ($0["model"] as? String) }.map(normalized))
    }
}

/// One line of `POST /api/pull`'s answer: `{"status","digest","total","completed"}` or `{"error"}`.
struct OllamaPullLine: Equatable {
    let status: String?
    let total: Double?
    let completed: Double?
    let error: String?

    init?(_ line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return nil }
        status = object["status"] as? String
        total = (object["total"] as? NSNumber)?.doubleValue
        completed = (object["completed"] as? NSNumber)?.doubleValue
        error = object["error"] as? String
    }

    var fraction: Double? {
        guard let total, total > 0, let completed else { return nil }
        return min(max(completed / total, 0), 1)
    }
}

public struct SystemOllamaClient: OllamaControlling {
    public static let port = 11434
    private let base = URL(string: "http://127.0.0.1:\(SystemOllamaClient.port)")!

    public init() {}

    private func session(timeout: TimeInterval, delegate: URLSessionDelegate? = nil) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = 24 * 3600
        configuration.connectionProxyDictionary = [:]
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    private func get(_ path: String) async throws -> Data {
        let session = session(timeout: 3)
        defer { session.finishTasksAndInvalidate() }
        let request = URLRequest(url: base.appendingPathComponent(path))
        return try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: request) { data, response, error in
                if let error { continuation.resume(throwing: error) }
                else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    continuation.resume(throwing: OllamaError.badAnswer)
                } else { continuation.resume(returning: data ?? Data()) }
            }.resume()
        }
    }

    public func isRunning() async -> Bool { (try? await get("api/version")) != nil }

    public func installedModels() async throws -> Set<String> {
        let data: Data
        do { data = try await get("api/tags") } catch { throw OllamaError.notRunning }
        guard let names = OllamaNames.parseTags(data) else { throw OllamaError.badAnswer }
        return names
    }

    public func pull(_ model: String, progress: @escaping @Sendable (Double?, String) async -> Void) async throws {
        var request = URLRequest(url: base.appendingPathComponent("api/pull"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "stream": true])
        let reader = PullStreamReader(progress: progress)
        // Ollama sends a line at least every few seconds while it downloads; five quiet minutes means it is stuck.
        let session = session(timeout: 300, delegate: reader)
        defer { session.finishTasksAndInvalidate() }
        try await withTaskCancellationHandler {
            try await reader.run(session.dataTask(with: request))
        } onCancel: {
            session.invalidateAndCancel()
        }
    }
}

/// Splits the streamed answer into lines and hands each to `progress`; finishes when Ollama says "success".
private final class PullStreamReader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var failure: String?
    private var succeeded = false
    private var statusCode = 200
    private var continuation: CheckedContinuation<Void, Error>?
    private let progress: @Sendable (Double?, String) async -> Void
    private var lastReport = Date.distantPast

    init(progress: @escaping @Sendable (Double?, String) async -> Void) {
        self.progress = progress
    }

    func run(_ task: URLSessionDataTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock(); self.continuation = continuation; lock.unlock()
            task.resume()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock(); statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200; lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        buffer.append(data)
        var lines: [OllamaPullLine] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer = Data(buffer[buffer.index(after: newline)...])
            if let parsed = OllamaPullLine(Data(line)) { lines.append(parsed) }
        }
        var report: (Double?, String)?
        for line in lines {
            if let error = line.error { failure = error }
            if line.status == "success" { succeeded = true }
            if let status = line.status, Date().timeIntervalSince(lastReport) > 0.5 || line.status == "success" {
                lastReport = Date()
                report = (line.fraction, status)
            }
        }
        lock.unlock()
        if let report { Task { await progress(report.0, report.1) } }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        if !buffer.isEmpty, let line = OllamaPullLine(buffer) {
            if let message = line.error { failure = message }
            if line.status == "success" { succeeded = true }
        }
        let continuation = self.continuation
        self.continuation = nil
        let result: Result<Void, Error>
        if let failure { result = .failure(OllamaError.refused(failure)) }
        else if let error { result = .failure(error) }
        else if !(200..<300).contains(statusCode) { result = .failure(OllamaError.refused("Ollama answered with HTTP \(statusCode).")) }
        else if succeeded { result = .success(()) }
        else { result = .failure(OllamaError.badAnswer) }
        lock.unlock()
        continuation?.resume(with: result)
    }
}
