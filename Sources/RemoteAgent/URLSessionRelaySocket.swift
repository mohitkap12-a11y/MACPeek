#if canImport(Network)
import Foundation

/// The relay socket on macOS: a `URLSessionWebSocketTask`. TLS to the relay is checked as for any HTTPS site; the
/// sessions inside are protected end to end on their own.
public final class URLSessionRelaySocket: RelaySocket, @unchecked Sendable {
    private let task: URLSessionWebSocketTask
    private let session: URLSession

    public static let factory: RelaySocketFactory = { url in URLSessionRelaySocket(url: url) }

    public init(url: URL) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
        var request = URLRequest(url: url)
        request.setValue("MacPeek/\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development")",
                         forHTTPHeaderField: "User-Agent")
        task = session.webSocketTask(with: request)
        // The relay limits messages to 256 KiB; the Mac never receives more than that in one.
        task.maximumMessageSize = 1024 * 1024
        task.resume()
    }

    public func send(_ message: RelaySocketMessage) async throws {
        switch message {
        case .text(let text): try await task.send(.string(text))
        case .data(let data): try await task.send(.data(data))
        }
    }

    public func receive() async throws -> RelaySocketMessage? {
        do {
            switch try await task.receive() {
            case .string(let text): return .text(text)
            case .data(let data): return .data(data)
            @unknown default: return nil
            }
        } catch {
            // Closed by the relay (its reason came as a text message first) or by us.
            if task.closeCode != .invalid || task.state != .running { return nil }
            throw error
        }
    }

    public func close() {
        task.cancel(with: .normalClosure, reason: nil)
        session.invalidateAndCancel()
    }
}
#endif
