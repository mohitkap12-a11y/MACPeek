import Foundation
import RemoteCrypto

/// The MacPeek Remote service this Mac talks to for "Add to my account" and the relay, the first of:
/// `MACPEEK_API_URL` in the environment; `remote.serviceURL` in MacPeek's defaults
/// (`defaults write app.macpeek.MacPeek remote.serviceURL https://api.staging.macpeekapp.com`); the address the app was
/// built for (Info.plist `MacPeekAPIURL`, set by scripts/build-app.sh: `MACPEEK_ENV=staging` builds use staging, like
/// MacPeek Remote's); else production.
public enum AccountService {
    public static let production = URL(string: "https://api.macpeekapp.com")!

    public static func baseURL(environment: [String: String] = ProcessInfo.processInfo.environment,
                               defaults: UserDefaults = .standard,
                               built: String? = Bundle.main.object(forInfoDictionaryKey: "MacPeekAPIURL") as? String) -> URL {
        for candidate in [environment["MACPEEK_API_URL"], defaults.string(forKey: "remote.serviceURL"), built] {
            if let candidate, let url = URL(string: candidate), url.scheme == "https" || url.scheme == "http" { return url }
        }
        return production
    }

    /// The relay next to an API: `relay.` in place of `api.`, over WebSockets; the API itself elsewhere (development).
    public static func relayURL(for api: URL) -> URL {
        guard var components = URLComponents(url: api, resolvingAgainstBaseURL: false), let host = components.host else { return api }
        if host.hasPrefix("api.") { components.host = "relay." + host.dropFirst(4) }
        components.scheme = components.scheme == "http" ? "ws" : "wss"
        components.path = ""
        return components.url ?? api
    }
}

/// One HTTP request to the service. The macOS app uses URLSession; tests use a fake.
public protocol AccountHTTP: Sendable {
    func send(_ method: String, _ url: URL, headers: [String: String], body: Data?) async throws -> (status: Int, body: Data)
}

/// "Add to my account" on this Mac, step by step (`AccountJoin` in RemoteCrypto describes the protocol): ask the service,
/// let the person sign in on the web, wait for a console of the account to approve, then join. `onPhase` is told every
/// change; the app shows it in Settings ▸ Remote management.
public actor AccountJoinFlow {
    public enum Phase: Equatable, Sendable {
        case idle
        case starting
        /// Waiting for the person to sign in on this page and add the Mac.
        case signIn(URL)
        /// Added on the web; waiting for a console of the account to approve.
        case waitingForApproval(account: String)
        /// Approved: sending the claim and joining.
        case joining
        case joined(account: String)
        case failed(String)
    }

    private struct Request {
        let id: String
        let secret: String
    }

    private let state: AgentState
    private let identity: DeviceIdentity
    private let name: String
    private let role: ConsoleRole
    private let http: AccountHTTP
    private let baseURL: URL
    private let onPhase: @Sendable (Phase) -> Void
    private let clock: @Sendable () -> Date
    private var request: Request?
    private var account = ""
    public private(set) var phase: Phase = .idle {
        didSet { if phase != oldValue { onPhase(phase) } }
    }

    /// `role` is the most the account's devices may do here: View and act unless the app says otherwise. Actions still
    /// need the separate "Allow actions" switch on this Mac.
    public init(state: AgentState, identity: DeviceIdentity, name: String, role: ConsoleRole = .viewAndAct, http: AccountHTTP,
                baseURL: URL = AccountService.baseURL(), clock: @escaping @Sendable () -> Date = Date.init,
                onPhase: @escaping @Sendable (Phase) -> Void = { _ in }) {
        self.state = state
        self.identity = identity
        // One line of at most 64 characters, trimmed as the service trims it before checking the signature.
        let line = name.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        let trimmed = String(line.trimmingCharacters(in: .whitespaces).prefix(64)).trimmingCharacters(in: .whitespaces)
        self.name = trimmed.isEmpty ? "Mac" : trimmed
        self.role = role
        self.http = http
        self.baseURL = baseURL
        self.clock = clock
        self.onPhase = onPhase
    }

    /// Asks the service. On success the phase is `.signIn(url)`: open the page, then call `poll` every few seconds.
    public func start() async {
        phase = .starting
        let time = Int64((clock().timeIntervalSince1970 * 1000).rounded())
        do {
            let signature = try AccountJoin.request(by: identity, name: name, time: time)
            let reply = try await call("POST", "/mac-joins", body: [
                "macKey": identity.publicIdentity.signingKey.base64EncodedString(), "name": name, "time": Int(time),
                "signature": signature.base64EncodedString(),
            ])
            guard let id = reply["id"] as? String, let secret = reply["secret"] as? String,
                  let page = (reply["url"] as? String).flatMap(URL.init(string:)) else { throw Failure.unexpected }
            request = Request(id: id, secret: secret)
            phase = .signIn(page)
        } catch {
            phase = .failed(Self.describe(error))
        }
    }

    /// Checks the request once and moves on when something changed. Once a console approved, the Mac joins on its own.
    /// Does nothing once the flow has finished or failed.
    public func poll() async {
        guard let request else { return }
        switch phase {
        case .signIn, .waitingForApproval: break
        default: return
        }
        do {
            let reply = try await call("GET", "/mac-joins/\(request.id)", secret: request.secret)
            account = reply["account"] as? String ?? account
            switch reply["status"] as? String {
            case "waiting": return
            case "attached": phase = .waitingForApproval(account: account)
            case "approved":
                guard let text = reply["grant"] as? String,
                      let grant = try? JSONDecoder().decode(WorkspaceGrant.self, from: Data(text.utf8)), grant.isValid(),
                      grant.workspaceID == reply["workspaceId"] as? String else {
                    throw Failure.message("The approval from your account does not check out. Start again.")
                }
                try await join(grant, request: request)
            case "declined": phase = .failed("The request was declined in MacPeek Remote.")
            case "joined": phase = .joined(account: account)
            default: throw Failure.unexpected
            }
        } catch {
            phase = .failed(Self.describe(error))
        }
    }

    /// The service records the claim first: if that fails nothing changed here, and the person can start again.
    private func join(_ grant: WorkspaceGrant, request: Request) async throws {
        phase = .joining
        let claim = try await state.claimForJoining(grant)
        _ = try await call("POST", "/mac-joins/\(request.id)/claim", secret: request.secret, body: ["claim": [
            "macKey": claim.macKey.base64EncodedString(), "time": Int(claim.time), "signature": claim.signature.base64EncodedString(),
        ]])
        try await state.joinAccount(grant, roleCap: role)
        phase = .joined(account: account.isEmpty ? grant.name : account)
    }

    /// Stops here, and tells the service when a request was made.
    public func cancel() async {
        if let request, phase != .idle {
            switch phase {
            case .joined, .joining: break
            default: _ = try? await call("POST", "/mac-joins/\(request.id)/cancel", secret: request.secret)
            }
        }
        request = nil
        phase = .idle
    }

    // MARK: HTTP

    enum Failure: Error, Equatable {
        case status(Int, String?)
        case unexpected
        case message(String)
    }

    private func call(_ method: String, _ path: String, secret: String? = nil, body: [String: Any]? = nil) async throws -> [String: Any] {
        var headers = ["Accept": "application/json"]
        if let secret { headers["X-Join-Secret"] = secret }
        var data: Data?
        if let body {
            headers["Content-Type"] = "application/json"
            data = try JSONSerialization.data(withJSONObject: body)
        }
        let url = baseURL.appendingPathComponent(String(path.dropFirst()))
        let (status, reply) = try await http.send(method, url, headers: headers, body: data)
        let object = (try? JSONSerialization.jsonObject(with: reply)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status) else { throw Failure.status(status, object["error"] as? String) }
        return object
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case Failure.status(404, _): return "The request expired or was cancelled. Start again."
        case Failure.status(429, _): return "Too many tries. Wait a few minutes and start again."
        case Failure.status(400, "clock_skew"?): return "This Mac's clock is wrong. Set the date and time automatically, then start again."
        case Failure.status(_, let code?): return "MacPeek Remote's service refused the request (\(code)). Start again."
        case Failure.status(let status, nil): return "MacPeek Remote's service answered with an error (HTTP \(status)). Start again."
        case Failure.message(let message): return message
        case Failure.unexpected: return "MacPeek Remote's service answered something unexpected. Update MacPeek."
        case let refusal as AgentRefusal: return refusal.message
        default: return "Could not reach MacPeek Remote's service: \(error.localizedDescription)"
        }
    }
}

#if canImport(Network)
/// The service over URLSession, on macOS.
public struct URLSessionAccountHTTP: AccountHTTP {
    public init() {}

    public func send(_ method: String, _ url: URL, headers: [String: String], body: Data?) async throws -> (status: Int, body: Data) {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        request.httpBody = body
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        let (data, response) = try await URLSession(configuration: configuration).data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }
}
#endif
