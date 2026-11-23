import XCTest
import MacPeekCore
import CPUPeekKit
import PortPeekKit
import ProcessPeekKit
import DNSPeekKit
import RemoteCrypto
import RemoteProtocol
@testable import RemoteAgent

// MARK: Fakes

private struct Unreadable: Error {}

private final class MemoryStore: AgentStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var log = ActivityLog()
    private var membership: WorkspaceMembership?

    private func locked<Value>(_ body: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    func loadLog() throws -> ActivityLog { locked { log } }
    func saveLog(_ log: ActivityLog) throws { locked { self.log = log } }
    func loadMembership() throws -> WorkspaceMembership? { locked { membership } }
    func saveMembership(_ membership: WorkspaceMembership?) throws { locked { self.membership = membership } }
}

/// What the agent sent and whether it closed, collected from the transport side.
private actor Outbox {
    private var reader = Framing.Reader()
    private(set) var messages: [WireMessage] = []
    /// Frames that are not messages: a tunnel's sealed bytes.
    private(set) var raw: [Data] = []
    private(set) var closed = false

    func append(_ bytes: Data) throws {
        for frame in try reader.append(bytes) {
            if let message = try? WireMessage.decoded(from: frame) { messages.append(message) } else { raw.append(frame) }
        }
    }

    func takeRaw() -> [Data] {
        defer { raw.removeAll() }
        return raw
    }

    func markClosed() { closed = true }

    func take() -> [WireMessage] {
        defer { messages.removeAll() }
        return messages
    }
}

private let port = PortInfo(port: 3000, protocolType: .tcp, address: "*", processName: "node", pid: 4242)
private let device = DeviceInfo(computerName: "Studio", localHostName: "studio", modelIdentifier: "Mac14,13",
                                macOSVersion: "14.5", bootTime: nil)

private actor ActionCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

private func readers() -> AgentReaders {
    AgentReaders(device: { device }, cpuTopology: { CPUTopology(chip: "M2", logicalCores: 8, groups: []) },
                 cpuSnapshot: { throw Unreadable() }, memory: { throw Unreadable() }, processUsage: { throw Unreadable() },
                 volumes: { throw Unreadable() }, networkCounters: { throw Unreadable() },
                 networkSnapshot: { throw Unreadable() }, ports: { [port] }, processes: { throw Unreadable() },
                 sleep: { throw Unreadable() },
                 dnsConfiguration: { dnsConfiguration },
                 dnsProbe: { server, _ in ServerProbe(server: server, outcome: .answered(queryMilliseconds: 12, status: "NOERROR", answers: 1)) })
}

private let dnsConfiguration = DNSConfiguration(
    resolvers: [DNSResolver(id: "1", number: 1, nameservers: ["192.168.1.1"], domain: nil, searchDomains: [], interface: "en0",
                            options: nil, timeoutSeconds: nil, flags: [], reachability: "Reachable", order: nil, isScoped: false)],
    scopedResolvers: [])

private func actions(_ counter: ActionCounter) -> AgentActions {
    AgentActions(freePort: { _, _ in await counter.increment(); return .terminated },
                 quitProcess: { _, _ in await counter.increment(); return .terminated })
}

/// `XCTUnwrap` takes an autoclosure, which cannot `await` on Swift 5.9.
private func unwrapped<Value>(_ value: Value?, file: StaticString = #filePath, line: UInt = #line) throws -> Value {
    try XCTUnwrap(value, file: file, line: line)
}

// MARK: Harness

private final class Harness {
    let store = MemoryStore()
    let state: AgentState
    let counter = ActionCounter()
    let handler: RequestHandler
    let macIdentity = DeviceIdentity(name: "Studio")

    init(settings: RemoteSettings = RemoteSettings(isEnabled: true, allowActions: true),
         tunnelDialer: TunnelDialing = UnavailableTunnelDialer()) {
        state = AgentState(identity: macIdentity, store: store, settings: settings)
        handler = RequestHandler(readers: readers(), actions: actions(counter), agentVersion: "0.3.0", tunnelDialer: tunnelDialer)
    }

    func connect(allowsTunnels: Bool = true, viaRelay: Bool = false) async -> (AgentConnection, Outbox) {
        let outbox = Outbox()
        let connection = AgentConnection(state: state, handler: handler, send: { try? await outbox.append($0) },
                                         onClose: { await outbox.markClosed() }, allowsTunnels: allowsTunnels, viaRelay: viaRelay)
        await connection.start()
        return (connection, outbox)
    }
}

private func deliver(_ message: WireMessage, to connection: AgentConnection) async throws {
    await connection.receive(Framing.frame(try message.encoded()))
}

/// Adds the harness's Mac to `account` as "Add to my account" does once a console approved; `roleCap` is the most the
/// account's devices may do here.
private func join(_ harness: Harness, _ account: Account, roleCap: ConsoleRole = .viewAndAct) async throws {
    try await harness.state.joinAccount(try account.grant(for: DeviceIdentity(name: "Main Mac")), roleCap: roleCap)
}

/// A device of `account` connected to the harness's Mac. The Mac must have joined the account.
private func accountDevice(_ harness: Harness, _ account: Account, name: String = "Laptop", role: WorkspaceRole = .owner,
                           allowsTunnels: Bool = true) async throws -> Session {
    let identity = DeviceIdentity(name: name)
    return try await Session(harness, identity: identity, chain: try account.chain(for: identity, role: role), allowsTunnels: allowsTunnels)
}

/// A console session over the handshake, sending requests and reading responses.
private final class Session {
    let connection: AgentConnection
    let outbox: Outbox
    var channel: SecureChannel

    init(_ harness: Harness, identity: DeviceIdentity, chain: WorkspaceChain? = nil, allowsTunnels: Bool = true) async throws {
        (connection, outbox) = await harness.connect(allowsTunnels: allowsTunnels, viaRelay: !allowsTunnels)
        var handshake = ConsoleHandshake(identity: identity, chain: chain)
        try await deliver(.hello(handshake.hello()), to: connection)
        guard case .reply(let reply)? = await outbox.take().first else { throw Unreadable() }
        let macKey = harness.macIdentity.publicIdentity
        let result = try handshake.finish(after: reply) { $0.isSameDevice(as: macKey) }
        channel = result.channel
        try await deliver(.finish(result.finish), to: connection)
    }

    func send(_ request: Envelope) async throws -> Envelope? {
        try await deliver(.sealed(channel.seal(JSONEncoder().encode(request))), to: connection)
        guard case .sealed(let frame)? = await outbox.take().first else { return nil }
        return try JSONDecoder().decode(Envelope.self, from: channel.open(frame))
    }
}

// MARK: Tests

final class AgentModelTests: XCTestCase {
    func testSettingsAreOffByDefault() {
        let settings = RemoteSettings()
        XCTAssertFalse(settings.isEnabled)
        XCTAssertFalse(settings.allowActions)
    }

    func testActivityLogDetectsEdits() throws {
        var log = ActivityLog()
        log.append(actor: "Laptop", fingerprint: "aaaa", event: "Quit node (PID 1)", outcome: "Done")
        log.append(actor: "Laptop", fingerprint: "aaaa", event: "Free port 3000", outcome: "Done")
        XCTAssertTrue(log.isIntact)

        let data = try JSONEncoder().encode(log)
        let edited = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "Free port 3000", with: "Nothing")
        XCTAssertFalse(try JSONDecoder().decode(ActivityLog.self, from: Data(edited.utf8)).isIntact)

        log.append(actor: "This Mac", fingerprint: nil, event: "Revoked Laptop", outcome: "Done")
        XCTAssertFalse(ActivityLog(entries: [log.entries[0], log.entries[2]]).isIntact, "A removed entry breaks the chain")
        XCTAssertFalse(ActivityLog(entries: log.entries.reversed()).isIntact)
    }

    func testActivityLogKeepsTheNewestEntries() {
        var log = ActivityLog()
        for index in 0..<(ActivityLog.limit + 5) { log.append(actor: "This Mac", fingerprint: nil, event: "\(index)", outcome: "") }
        XCTAssertEqual(log.entries.count, ActivityLog.limit)
        XCTAssertEqual(log.entries.last?.event, "\(ActivityLog.limit + 4)")
        XCTAssertTrue(log.isIntact)
    }

    func testFileStoreKeepsTheLogPrivately() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileAgentStore(directory: directory)
        XCTAssertEqual(try store.loadLog(), ActivityLog())
        var log = ActivityLog()
        log.append(actor: "This Mac", fingerprint: nil, event: "Turned Remote management on", outcome: "Done")
        try store.saveLog(log)
        XCTAssertEqual(try store.loadLog(), log)
        let path = directory.appendingPathComponent("activity-log.json").path
        let permissions = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
    }
}

// MARK: Workspaces (protocol version 2)

/// An account as MacPeek Remote builds it: a workspace key, the owner's member key, and certified devices.
private struct Account {
    let id = "ws_test"
    let key = WorkspaceKeys.newPrivateKey()
    let memberKey = WorkspaceKeys.newPrivateKey()

    var publicKey: Data { try! WorkspaceKeys.publicKey(of: key) }

    func chain(for device: DeviceIdentity, role: WorkspaceRole = .owner) throws -> WorkspaceChain {
        let member = try MemberCertificate.issue(workspaceID: id, memberID: "m_owner", signingKey: WorkspaceKeys.publicKey(of: memberKey),
                                                 role: role, issuedAt: 1, issuerPrivateKey: key)
        let certificate = try DeviceCertificate.issue(workspaceID: id, memberID: "m_owner", deviceID: "d_\(device.name)",
                                                      signingKey: device.publicIdentity.signingKey, name: device.name,
                                                      issuedAt: 1, memberPrivateKey: memberKey)
        return WorkspaceChain(members: [member], device: certificate)
    }

    func grant(for device: DeviceIdentity) throws -> WorkspaceGrant {
        WorkspaceGrant(workspaceID: id, workspaceKey: publicKey, name: "me@example.com", chain: try chain(for: device))
    }

    func revocations(_ sequence: Int, _ devices: [DeviceIdentity]) throws -> RevocationList {
        try RevocationList.issue(workspaceID: id, sequence: sequence, revokedKeys: devices.map(\.publicIdentity.signingKey),
                                 workspacePrivateKey: key)
    }
}

final class AgentSessionTests: XCTestCase {
    func testNobodyConnectsBeforeTheMacJoinsAnAccount() async throws {
        let harness = Harness()
        let (connection, outbox) = await harness.connect()
        var handshake = ConsoleHandshake(identity: DeviceIdentity(name: "Laptop"), chain: try Account().chain(for: DeviceIdentity(name: "Laptop")))
        try await deliver(.hello(handshake.hello()), to: connection)
        guard case .refused(let reason)? = await outbox.take().first else { return XCTFail("Expected a refusal") }
        XCTAssertTrue(reason.contains("Add to my account"))
        let closed = await outbox.closed
        XCTAssertTrue(closed)
    }

    func testADeviceOfTheAccountReadsOverAnEncryptedSession() async throws {
        let harness = Harness(), account = Account()
        try await join(harness, account, roleCap: .viewOnly)
        let session = try await accountDevice(harness, account)

        let capabilities = try unwrapped(try await session.send(.request(.capabilities))).body(Capabilities.self)
        XCTAssertEqual(capabilities.device, device)
        XCTAssertEqual(capabilities.agentVersion, "0.3.0")
        XCTAssertFalse(capabilities.actionsAllowed, "The Mac chose view only")

        let ports = try unwrapped(try await session.send(.request(.ports))).body([PortInfo].self)
        XCTAssertEqual(ports, [port])

        let failure = try unwrapped(try await session.send(.request(.memoryStats)))
        XCTAssertEqual(failure.kind, .error)
        XCTAssertEqual(try failure.body(RemoteError.self).code, .unavailable)

        let unknown = try unwrapped(try await session.send(.request("files.delete")))
        XCTAssertEqual(try unknown.body(RemoteError.self).code, .unknownOperation)
    }

    func testDNSProbesOnlyTheMacsOwnServers() async throws {
        let harness = Harness(), account = Account()
        try await join(harness, account)
        let session = try await accountDevice(harness, account)

        let configuration = try unwrapped(try await session.send(.request(.dnsConfiguration))).body(DNSConfiguration.self)
        XCTAssertEqual(configuration.activeServers, ["192.168.1.1"])

        let own = try Envelope.request(.dnsProbe, body: DNSProbeRequest(server: "192.168.1.1", name: "apple.com"))
        let probe = try unwrapped(try await session.send(own)).body(ServerProbe.self)
        XCTAssertEqual(probe.server, "192.168.1.1")

        let elsewhere = try Envelope.request(.dnsProbe, body: DNSProbeRequest(server: "203.0.113.9", name: "apple.com"))
        let elsewhereCode = try unwrapped(try await session.send(elsewhere)).body(RemoteError.self).code
        XCTAssertEqual(elsewhereCode, .notPermitted)

        let badName = try Envelope.request(.dnsProbe, body: DNSProbeRequest(server: "192.168.1.1", name: "-x; rm"))
        let badNameCode = try unwrapped(try await session.send(badName)).body(RemoteError.self).code
        XCTAssertEqual(badNameCode, .invalidPayload)
    }

    func testADeviceWithoutTheAccountsChainIsRefused() async throws {
        let harness = Harness()
        try await join(harness, Account())
        let (connection, outbox) = await harness.connect()
        var handshake = ConsoleHandshake(identity: DeviceIdentity(name: "Stranger"))
        try await deliver(.hello(handshake.hello()), to: connection)
        guard case .reply(let reply)? = await outbox.take().first else { return XCTFail() }
        let finish = try handshake.finish(after: reply) { _ in true }.finish
        try await deliver(.finish(finish), to: connection)
        guard case .refused? = await outbox.take().first else { return XCTFail("Expected a refusal") }
        let observed = await outbox.closed
        XCTAssertTrue(observed)
    }

    func testActionsNeedTheRoleAndTheSwitch() async throws {
        let request = try Envelope.request(.freePort, body: FreePortRequest(port: port))

        let viewOnly = Harness(), viewAccount = Account()
        try await join(viewOnly, viewAccount, roleCap: .viewOnly)
        let viewer = try await accountDevice(viewOnly, viewAccount)
        let viewerCode = try unwrapped(try await viewer.send(request)).body(RemoteError.self).code
        XCTAssertEqual(viewerCode, .notPermitted)

        let switchedOff = Harness(settings: RemoteSettings(isEnabled: true, allowActions: false)), offAccount = Account()
        try await join(switchedOff, offAccount)
        let actor = try await accountDevice(switchedOff, offAccount)
        let switchedOffCode = try unwrapped(try await actor.send(request)).body(RemoteError.self).code
        XCTAssertEqual(switchedOffCode, .actionsDisabled)

        let allowed = Harness(), allowedAccount = Account()
        try await join(allowed, allowedAccount)
        let operator_ = try await accountDevice(allowed, allowedAccount)
        let allowedResult = try unwrapped(try await operator_.send(request)).body(ActionResult.self).result
        XCTAssertEqual(allowedResult, .terminated)

        let counts = (await viewOnly.counter.count, await switchedOff.counter.count, await allowed.counter.count)
        XCTAssertEqual(counts.0, 0)
        XCTAssertEqual(counts.1, 0)
        XCTAssertEqual(counts.2, 1)

        // Every action, refused or not, is in the log, attributed to the device.
        let entries = await allowed.state.log.entries
        XCTAssertEqual(entries.last?.actor, "Laptop")
        XCTAssertEqual(entries.last?.event, "Free port 3000 (node, PID 4242)")
        XCTAssertEqual(entries.last?.outcome, "Done")
        let refused = await viewOnly.state.log.entries.last
        XCTAssertEqual(refused?.outcome, "Refused: This device has view-only access to this Mac.")
    }

    func testReplayedFrameEndsTheSession() async throws {
        let harness = Harness(), account = Account()
        try await join(harness, account)
        let session = try await accountDevice(harness, account)
        let frame = try session.channel.seal(JSONEncoder().encode(Envelope.request(.deviceInfo)))
        try await deliver(.sealed(frame), to: session.connection)
        _ = await session.outbox.take()
        try await deliver(.sealed(frame), to: session.connection)
        guard case .refused? = await session.outbox.take().first else { return XCTFail("Expected a refusal") }
        let observed = await session.outbox.closed
        XCTAssertTrue(observed)
    }

    func testTurningOffEndsSessionsAndRefusesNewOnes() async throws {
        let harness = Harness(), account = Account()
        try await join(harness, account)
        let session = try await accountDevice(harness, account)
        await harness.state.update(RemoteSettings(isEnabled: false))
        let closed = await session.outbox.closed
        XCTAssertTrue(closed)
        let again = try? await accountDevice(harness, account)
        let answered = try await again?.send(.request(.capabilities))
        XCTAssertNil(answered)
    }
}

final class AgentWorkspaceTests: XCTestCase {
    private func status(_ session: Session) async throws -> WorkspaceStatus {
        try unwrapped(try await session.send(.request(.workspaceStatus))).body(WorkspaceStatus.self)
    }

    func testJoiningAnAccountLetsEveryDeviceOfItIn() async throws {
        let harness = Harness(), account = Account()
        try await join(harness, account)
        let membership = try unwrapped(await harness.state.membership)
        XCTAssertEqual(membership.workspaceKey, account.publicKey)
        XCTAssertEqual(membership.roleCap, .viewAndAct, "View and act unless the Mac says otherwise")
        let logged = await harness.state.log.entries.last?.event
        XCTAssertEqual(logged, "Added this Mac to me@example.com's account")

        let session = try await accountDevice(harness, account, name: "Desk")
        let capabilities = try unwrapped(try await session.send(.request(.capabilities))).body(Capabilities.self)
        XCTAssertTrue(capabilities.actionsAllowed)
        XCTAssertEqual(capabilities.protocolVersion, 2)
        XCTAssertTrue(capabilities.operations.contains(.workspaceRevocations))
        let current = try await status(session)
        XCTAssertEqual(current.workspaceID, account.id)
        XCTAssertTrue(current.viaWorkspace)
        XCTAssertTrue(try unwrapped(current.claim).isValid)
        let devices = await harness.state.membership?.devices.map(\.identity.name)
        XCTAssertEqual(devices, ["Desk"])
    }

    func testViewersAndTheMacsChoiceLimitAccess() async throws {
        let harness = Harness(), account = Account()
        try await join(harness, account, roleCap: .viewOnly)
        let owner = try await accountDevice(harness, account)
        var capabilities = try unwrapped(try await owner.send(.request(.capabilities))).body(Capabilities.self)
        XCTAssertFalse(capabilities.actionsAllowed, "The Mac chose view only")

        await harness.state.setWorkspaceRoleCap(.viewAndAct)
        let session = try await accountDevice(harness, account, name: "Tablet", role: .viewer)
        capabilities = try unwrapped(try await session.send(.request(.capabilities))).body(Capabilities.self)
        XCTAssertFalse(capabilities.actionsAllowed, "A viewer never acts")
        let freed = try unwrapped(try await session.send(try .request(.freePort, body: FreePortRequest(port: port))))
        XCTAssertEqual(freed.kind, .error)
        let count = await harness.counter.count
        XCTAssertEqual(count, 0)
    }

    func testOtherAccountsAreRefused() async throws {
        let harness = Harness()
        try await join(harness, Account())
        let session = try await accountDevice(harness, Account(), name: "Stranger")
        let answer = try await session.send(.request(.capabilities))
        XCTAssertNil(answer)
        let closed = await session.outbox.closed
        XCTAssertTrue(closed)
    }

    func testRevocationEndsTheSessionAndOldListsAreIgnored() async throws {
        let harness = Harness(), account = Account()
        try await join(harness, account)
        let lost = DeviceIdentity(name: "Lost")
        let lostSession = try await Session(harness, identity: lost, chain: try account.chain(for: lost))
        let before = try await lostSession.send(.request(.capabilities))
        XCTAssertNotNil(before)

        let owner = try await accountDevice(harness, account)
        let after = try unwrapped(try await owner.send(try .request(.workspaceRevocations, body: try account.revocations(2, [lost]))))
            .body(WorkspaceStatus.self)
        XCTAssertEqual(after.revocationSequence, 2)
        let lostClosed = await lostSession.outbox.closed
        XCTAssertTrue(lostClosed, "The removed device's open session ends at once")

        // An older list cannot bring it back, and a list from another account is refused.
        let older = try unwrapped(try await owner.send(try .request(.workspaceRevocations, body: try account.revocations(1, []))))
        XCTAssertEqual(try older.body(WorkspaceStatus.self).revocationSequence, 2)
        let foreign = try unwrapped(try await owner.send(try .request(.workspaceRevocations, body: try Account().revocations(9, []))))
        XCTAssertEqual(foreign.kind, .error)

        let again = try await Session(harness, identity: lost, chain: try account.chain(for: lost))
        let refused = try await again.send(.request(.capabilities))
        XCTAssertNil(refused)
    }

    func testJoiningAnotherAccountEndsTheOldAccountsSessions() async throws {
        let harness = Harness(), first = Account(), second = Account()
        try await join(harness, first)
        let session = try await accountDevice(harness, first)
        try await join(harness, second)
        let closed = await session.outbox.closed
        XCTAssertTrue(closed)
        let workspaceKey = await harness.state.membership?.workspaceKey
        XCTAssertEqual(workspaceKey, second.publicKey)
    }

    func testLeavingTheAccountRefusesItsDevices() async throws {
        let harness = Harness(), account = Account()
        try await join(harness, account)
        let session = try await accountDevice(harness, account)
        let answered = try await session.send(.request(.capabilities))
        XCTAssertNotNil(answered)
        await harness.state.leaveWorkspace()
        let closed = await session.outbox.closed
        XCTAssertTrue(closed)
        let again = try? await accountDevice(harness, account)
        let refused = try await again?.send(.request(.capabilities))
        XCTAssertNil(refused)
    }

    func testFileStoreKeepsTheMembershipPrivately() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileAgentStore(directory: directory)
        XCTAssertNil(try store.loadMembership())
        let membership = WorkspaceMembership(workspaceID: "ws", workspaceKey: Data(repeating: 1, count: 32), name: "me",
                                             roleCap: .viewOnly, joinedAt: Date(timeIntervalSince1970: 1_700_000_000))
        try store.saveMembership(membership)
        XCTAssertEqual(try store.loadMembership(), membership)
        let path = directory.appendingPathComponent("workspace.json").path
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int, 0o600)
        try store.saveMembership(nil)
        XCTAssertNil(try store.loadMembership())
    }
}

// MARK: Relay ("Allow from anywhere")

/// The relay's side of the Mac's socket, in memory: what the relay sends is queued for `receive`; what the Mac sends
/// is collected.
private actor RelayPipe {
    private var queue: [RelaySocketMessage?] = []
    private var waiter: CheckedContinuation<RelaySocketMessage?, Never>?
    private(set) var sent: [RelaySocketMessage] = []

    func push(_ message: RelaySocketMessage?) {
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: message)
        } else {
            queue.append(message)
        }
    }

    func next() async -> RelaySocketMessage? {
        if !queue.isEmpty { return queue.removeFirst() }
        return await withCheckedContinuation { continuation in waiter = continuation }
    }

    func record(_ message: RelaySocketMessage) { sent.append(message) }
}

private final class FakeRelaySocket: RelaySocket, @unchecked Sendable {
    let pipe = RelayPipe()

    func send(_ message: RelaySocketMessage) async throws { await pipe.record(message) }
    func receive() async throws -> RelaySocketMessage? { await pipe.next() }
    func close() { Task { await pipe.push(nil) } }

    func push(control: [String: Any]) async {
        await pipe.push(.text(String(decoding: try! JSONSerialization.data(withJSONObject: control), as: UTF8.self)))
    }

    /// Waits up to two seconds for a message the Mac sent that `match` accepts.
    func sent<Value>(_ match: @escaping (RelaySocketMessage) -> Value?) async throws -> Value {
        for _ in 0..<200 {
            for message in await pipe.sent { if let value = match(message) { return value } }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw Unreadable()
    }
}

private func control(_ message: RelaySocketMessage) -> [String: Any]? {
    guard case .text(let text) = message else { return nil }
    return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
}

final class RelayTests: XCTestCase {
    /// Signed with Node's Ed25519 from a private key of 32 bytes of 7; macpeek-remote's cloud/test/relay.test.ts checks
    /// the same values.
    func testSharedVector() throws {
        let mac = try DeviceIdentity(name: "Studio", privateKeyData: Data(repeating: 7, count: 32))
        let macKey = mac.publicIdentity.signingKey
        XCTAssertEqual(RelayAuth.macID(of: macKey), "fe812c12f3ab4ce6ac5db69ac352f906cb1b11ef43fb33e252ef7ff552263889")
        XCTAssertEqual(try RelayAuth.message(macID: RelayAuth.macID(of: macKey), nonce: "bm9uY2U="),
                       "macpeek-relay-mac-v1\nfe812c12f3ab4ce6ac5db69ac352f906cb1b11ef43fb33e252ef7ff552263889\nbm9uY2U=")
        let signature = try XCTUnwrap(Data(base64Encoded:
            "H468qmrkgC89nbRF4DaLjtXMojHXJ71Fw0g/9vL2GlbZxBus8XP+x91Qb7VPhY9IK4kYjy13rIZHkluFb+m8Aw=="))
        XCTAssertTrue(RelayAuth.isValid(signature: signature, macKey: macKey, nonce: "bm9uY2U="))
        // CryptoKit's signatures are randomized, so the Mac's own answer differs from Node's but checks out the same way.
        let answer = try RelayAuth.answer(nonce: "bm9uY2U=", by: mac)
        XCTAssertEqual(answer.macKey, macKey)
        XCTAssertTrue(RelayAuth.isValid(signature: answer.signature, macKey: macKey, nonce: "bm9uY2U="))
        XCTAssertFalse(RelayAuth.isValid(signature: signature, macKey: macKey, nonce: "b3RoZXI="))
    }

    func testAnswersTheChallengeAndServesEachConsoleOnItsOwnStream() async throws {
        let harness = Harness()
        let socket = FakeRelaySocket()
        let session = RelaySession(socket: socket, state: harness.state, handler: harness.handler, identity: harness.macIdentity)
        let run = Task { try await session.run() }

        await socket.push(control: ["type": "challenge", "nonce": "bm9uY2U="])
        let auth = try await socket.sent { message in control(message).flatMap { $0["type"] as? String == "auth" ? $0 : nil } }
        let macKey = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(auth["macKey"] as? String)))
        let signature = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(auth["signature"] as? String)))
        XCTAssertEqual(macKey, harness.macIdentity.publicIdentity.signingKey)
        XCTAssertTrue(RelayAuth.isValid(signature: signature, macKey: macKey, nonce: "bm9uY2U="))
        await socket.push(control: ["type": "ready"])

        // A console says hello through the relay to a Mac in no account: the agent refuses on that stream only.
        await socket.push(control: ["type": "open", "stream": 7])
        var start = Data([0, 0, 0, 7])
        start.append(Framing.frame(try WireMessage.hello(ConsoleHandshake(identity: DeviceIdentity(name: "Laptop")).hello()).encoded()))
        await socket.pipe.push(.data(start))

        let reply = try await socket.sent { message -> Data? in
            guard case .data(let data) = message, data.prefix(4) == Data([0, 0, 0, 7]) else { return nil }
            return Data(data.dropFirst(4))
        }
        var reader = Framing.Reader()
        let frames = try reader.append(reply)
        guard case .refused(let reason)? = try frames.first.map({ try WireMessage.decoded(from: $0) }) else {
            return XCTFail("expected a refusal")
        }
        XCTAssertTrue(reason.contains("not in a MacPeek Remote account"))
        // And the relay is told the stream ended, so the console's socket closes.
        let closed = try await socket.sent { message in control(message).flatMap { $0["type"] as? String == "close" ? $0["stream"] as? Int : nil } }
        XCTAssertEqual(closed, 7)
        let remaining = await session.streamCount
        XCTAssertEqual(remaining, 0)

        // Data for a stream the Mac does not know is answered with a close.
        await socket.pipe.push(.data(Data([0, 0, 0, 9, 1])))
        let unknown = try await socket.sent { message in control(message).flatMap { $0["stream"] as? Int == 9 ? true : nil } }
        XCTAssertTrue(unknown)

        socket.close()
        do {
            try await run.value
            XCTFail("a session ends by throwing")
        } catch {
            XCTAssertEqual(error as? RelayEnd, .disconnected)
        }
    }

    func testStopsWhenTheMacIsNotInAnAccount() async throws {
        let harness = Harness()
        let socket = FakeRelaySocket()
        let session = RelaySession(socket: socket, state: harness.state, handler: harness.handler, identity: harness.macIdentity)
        await socket.push(control: ["type": "challenge", "nonce": "bm9uY2U="])
        await socket.push(control: ["type": "error", "error": "not_in_account"])
        do {
            try await session.run()
            XCTFail("expected notInAccount")
        } catch {
            XCTAssertEqual(error as? RelayEnd, .notInAccount)
        }
    }

    func testRefusesAnythingButAChallengeFirst() async throws {
        let harness = Harness()
        let socket = FakeRelaySocket()
        let session = RelaySession(socket: socket, state: harness.state, handler: harness.handler, identity: harness.macIdentity)
        await socket.pipe.push(.data(Data([0, 0, 0, 1])))
        do {
            try await session.run()
            XCTFail("expected a protocol error")
        } catch {
            XCTAssertEqual(error as? RelayEnd, .protocolError)
        }
    }

    /// After Wi-Fi went off and on, the old socket neither works nor fails: a relay that stopped answering pings ends
    /// the session, so the client connects again instead of waiting forever.
    func testGivesUpOnARelayThatWentSilent() async throws {
        let harness = Harness()
        let socket = FakeRelaySocket()
        let session = RelaySession(socket: socket, state: harness.state, handler: harness.handler, identity: harness.macIdentity)
        try await session.ping(silence: 60)
        let pinged = try await socket.sent { message -> Bool? in message == .text("ping") ? true : nil }
        XCTAssertTrue(pinged)
        try await Task.sleep(nanoseconds: 50_000_000)
        do {
            try await session.ping(silence: 0.01)
            XCTFail("a silent relay ends the session")
        } catch {
            XCTAssertEqual(error as? RelayEnd, .disconnected)
        }
    }

    func testBacksOffFromTwoSecondsToFiveMinutes() {
        XCTAssertEqual(RelayClient.backoff(after: 1, random: 1), 2)
        XCTAssertEqual(RelayClient.backoff(after: 2, random: 1), 4)
        XCTAssertEqual(RelayClient.backoff(after: 5, random: 1), 32)
        XCTAssertEqual(RelayClient.backoff(after: 20, random: 1), 300)
    }

    func testSettingsSavedBeforeTheRelayKeepItOff() throws {
        let old = try JSONDecoder().decode(RemoteSettings.self, from: Data(#"{"isEnabled":true,"allowActions":false}"#.utf8))
        XCTAssertEqual(old, RemoteSettings(isEnabled: true, allowActions: false, allowFromAnywhere: false))
        let round = try JSONDecoder().decode(RemoteSettings.self, from: JSONEncoder().encode(RemoteSettings(isEnabled: true, allowFromAnywhere: true)))
        XCTAssertTrue(round.allowFromAnywhere)
    }

    func testTurningAllowFromAnywhereOnIsLogged() async {
        let harness = Harness()
        await harness.state.update(RemoteSettings(isEnabled: true, allowActions: true, allowFromAnywhere: true))
        let log = await harness.state.snapshot().log
        XCTAssertTrue(log.entries.contains { $0.event == "Turned Allow from anywhere on" })
    }
}

// MARK: Add to my account (AccountJoinFlow)

/// The service's side of a join request (macpeek-remote cloud/src/joins.ts), in memory: what the Mac sent, and what the
/// test (standing in for the web page and a console) answers.
private actor FakeJoinService: AccountHTTP {
    var request: [String: Any] = [:]
    var status = "waiting"
    var grant: String?
    var claim: [String: Any]?
    var cancelled = false
    var failClaim = false
    let workspaceID: String

    init(workspaceID: String) { self.workspaceID = workspaceID }

    func failClaims() { failClaim = true }

    func set(status: String, grant: String? = nil) {
        self.status = status
        if let grant { self.grant = grant }
    }

    nonisolated func send(_ method: String, _ url: URL, headers: [String: String], body: Data?) async throws -> (status: Int, body: Data) {
        let object = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        return await handle(method, url.path, secret: headers["X-Join-Secret"], object)
    }

    private func reply(_ status: Int, _ object: [String: Any]) -> (status: Int, body: Data) {
        (status, try! JSONSerialization.data(withJSONObject: object))
    }

    private func handle(_ method: String, _ path: String, secret: String?, _ body: [String: Any]) -> (status: Int, body: Data) {
        if method == "POST", path == "/mac-joins" {
            request = body
            return reply(201, ["id": "join_1234567890abcdef", "secret": "secret-secret-secret-secret",
                               "url": "https://remote.macpeekapp.com/account/join/?id=join_1234567890abcdef"])
        }
        guard secret == "secret-secret-secret-secret" else { return reply(404, ["error": "not_found"]) }
        switch (method, path) {
        case ("GET", "/mac-joins/join_1234567890abcdef"):
            let approved = status == "approved"
            return reply(200, ["status": status, "account": "me@example.com", "workspaceId": workspaceID,
                               "grant": approved ? (grant.map { $0 as Any } ?? NSNull()) : NSNull()])
        case ("POST", "/mac-joins/join_1234567890abcdef/claim"):
            guard status == "approved" else { return reply(409, ["error": "not_approved"]) }
            if failClaim { return reply(503, ["error": "unavailable"]) }
            claim = body["claim"] as? [String: Any]
            status = "joined"
            return reply(200, ["status": "joined"])
        case ("POST", "/mac-joins/join_1234567890abcdef/cancel"):
            cancelled = true
            status = "declined"
            return reply(200, ["status": "declined"])
        default:
            return reply(404, ["error": "not_found"])
        }
    }
}

final class AccountJoinTests: XCTestCase {
    private let base = URL(string: "https://api.macpeekapp.com")!

    func testJoinsAfterTheWebSignInAndTheConsolesApproval() async throws {
        let harness = Harness(), account = Account()
        let service = FakeJoinService(workspaceID: account.id)
        let flow = AccountJoinFlow(state: harness.state, identity: harness.macIdentity, name: "Office\nMac", http: service, baseURL: base)

        await flow.start()
        let started = await flow.phase
        XCTAssertEqual(started, .signIn(URL(string: "https://remote.macpeekapp.com/account/join/?id=join_1234567890abcdef")!))
        // The request is signed by the Mac's key and names it on one line.
        let request = await service.request
        let macKey = try unwrapped(Data(base64Encoded: request["macKey"] as? String ?? ""))
        XCTAssertEqual(macKey, harness.macIdentity.publicIdentity.signingKey)
        XCTAssertEqual(request["name"] as? String, "Office Mac")
        let time = try unwrapped(request["time"] as? Int)
        let message = try AccountJoin.requestMessage(macKey: macKey, name: "Office Mac", time: Int64(time))
        XCTAssertTrue(harness.macIdentity.publicIdentity.isValidSignature(
            try unwrapped(Data(base64Encoded: request["signature"] as? String ?? "")), for: Data(message.utf8)))

        await flow.poll()
        let stillWaiting = await flow.phase
        XCTAssertEqual(stillWaiting, started)

        await service.set(status: "attached")
        await flow.poll()
        let attached = await flow.phase
        XCTAssertEqual(attached, .waitingForApproval(account: "me@example.com"))

        // A console approves with the workspace grant: the Mac sends its claim and joins, with nothing to confirm here.
        let consoleDevice = DeviceIdentity(name: "Main Mac")
        let grant = try account.grant(for: consoleDevice)
        await service.set(status: "approved", grant: String(decoding: try JSONEncoder().encode(grant), as: UTF8.self))
        await flow.poll()
        let joined = await flow.phase
        XCTAssertEqual(joined, .joined(account: "me@example.com"))
        let membership = try unwrapped(await harness.state.membership)
        XCTAssertEqual(membership.workspaceID, account.id)
        XCTAssertEqual(membership.workspaceKey, account.publicKey)
        XCTAssertEqual(membership.roleCap, .viewAndAct, "View and act by default; actions still need Allow actions")
        let claim = try unwrapped(await service.claim)
        let sent = MacClaim(macKey: try unwrapped(Data(base64Encoded: claim["macKey"] as? String ?? "")), workspaceID: account.id,
                            time: Int64(try unwrapped(claim["time"] as? Int)),
                            signature: try unwrapped(Data(base64Encoded: claim["signature"] as? String ?? "")))
        XCTAssertTrue(sent.isValid)
        // The console that approved now reaches the Mac through the account.
        let authorized = await harness.state.authorize(consoleDevice.publicIdentity, chain: grant.chain)
        XCTAssertNotNil(authorized)
    }

    func testRefusesAGrantThatDoesNotCheckOut() async throws {
        let harness = Harness(), account = Account(), other = Account()
        let service = FakeJoinService(workspaceID: account.id)
        let flow = AccountJoinFlow(state: harness.state, identity: harness.macIdentity, name: "Office Mac", http: service, baseURL: base)
        await flow.start()
        // A chain issued by another workspace key than the one the grant names.
        let device = DeviceIdentity(name: "Main Mac")
        let forged = WorkspaceGrant(workspaceID: account.id, workspaceKey: account.publicKey, name: "me@example.com",
                                    chain: try other.chain(for: device))
        await service.set(status: "approved", grant: String(decoding: try JSONEncoder().encode(forged), as: UTF8.self))
        await flow.poll()
        let phase = await flow.phase
        guard case .failed = phase else { return XCTFail("expected a failure, got \(phase)") }
        let claim = await service.claim
        XCTAssertNil(claim, "The Mac claims nothing for a grant it cannot check")
        let membership = await harness.state.membership
        XCTAssertNil(membership)
    }

    func testCancellingTellsTheServiceAndJoinsNothing() async throws {
        let harness = Harness()
        let service = FakeJoinService(workspaceID: "ws_test")
        let flow = AccountJoinFlow(state: harness.state, identity: harness.macIdentity, name: "Office Mac", http: service, baseURL: base)
        await flow.start()
        await service.set(status: "attached")
        await flow.poll()
        await flow.cancel()
        let cancelled = await service.cancelled
        XCTAssertTrue(cancelled)
        let phase = await flow.phase
        XCTAssertEqual(phase, .idle)
        await service.set(status: "declined")
        await flow.poll()
        let after = await flow.phase
        XCTAssertEqual(after, .idle, "A cancelled flow stops checking")
    }

    func testJoinsNothingWhenTheServiceDoesNotTakeTheClaim() async throws {
        let harness = Harness(), account = Account()
        let service = FakeJoinService(workspaceID: account.id)
        let flow = AccountJoinFlow(state: harness.state, identity: harness.macIdentity, name: "Office Mac", http: service, baseURL: base)
        await flow.start()
        await service.failClaims()
        await service.set(status: "approved", grant: String(decoding: try JSONEncoder().encode(try account.grant(for: DeviceIdentity(name: "Main Mac"))), as: UTF8.self))
        await flow.poll()
        let phase = await flow.phase
        guard case .failed = phase else { return XCTFail("expected a failure, got \(phase)") }
        let membership = await harness.state.membership
        XCTAssertNil(membership, "The Mac joins only once the service has its claim, so it can start again")
    }

    func testSaysWhenTheConsoleDeclined() async throws {
        let harness = Harness()
        let service = FakeJoinService(workspaceID: "ws_test")
        let flow = AccountJoinFlow(state: harness.state, identity: harness.macIdentity, name: "Office Mac", http: service, baseURL: base)
        await flow.start()
        await service.set(status: "declined")
        await flow.poll()
        let phase = await flow.phase
        XCTAssertEqual(phase, .failed("The request was declined in MacPeek Remote."))
    }

    func testJoiningNeedsRemoteManagementOn() async throws {
        let harness = Harness(settings: RemoteSettings(isEnabled: false))
        do {
            try await harness.state.joinAccount(try Account().grant(for: DeviceIdentity(name: "Main Mac")), roleCap: .viewOnly)
            XCTFail("expected a refusal")
        } catch {}
    }

    func testServiceAddresses() {
        let defaults = UserDefaults(suiteName: "AccountServiceTests-\(UUID().uuidString)")!
        XCTAssertEqual(AccountService.baseURL(environment: [:], defaults: defaults, built: nil), AccountService.production)
        // Built for staging (scripts/build-app.sh with MACPEEK_ENV=staging); a placeholder left unsubstituted is ignored.
        XCTAssertEqual(AccountService.baseURL(environment: [:], defaults: defaults, built: "https://api.staging.macpeekapp.com").host,
                       "api.staging.macpeekapp.com")
        XCTAssertEqual(AccountService.baseURL(environment: [:], defaults: defaults, built: "__API_URL__"), AccountService.production)
        XCTAssertEqual(AccountService.baseURL(environment: ["MACPEEK_API_URL": "https://api.staging.macpeekapp.com"], defaults: defaults).absoluteString,
                       "https://api.staging.macpeekapp.com")
        defaults.set("https://api.staging.macpeekapp.com", forKey: "remote.serviceURL")
        XCTAssertEqual(AccountService.baseURL(environment: [:], defaults: defaults, built: nil).host, "api.staging.macpeekapp.com")
        XCTAssertEqual(AccountService.relayURL(for: AccountService.production).absoluteString, "wss://relay.macpeekapp.com")
        XCTAssertEqual(AccountService.relayURL(for: URL(string: "https://api.staging.macpeekapp.com")!).absoluteString,
                       "wss://relay.staging.macpeekapp.com")
        XCTAssertEqual(AccountService.relayURL(for: URL(string: "http://localhost:8787")!).absoluteString, "ws://localhost:8787")
    }
}


// MARK: Tunnels (Pro)

/// A TCP connection on the Mac, in memory: what the tunnel sent it, and bytes to hand back.
private final class FakeTunnelSocket: TunnelSocket, @unchecked Sendable {
    private let lock = NSLock()
    private var sentData: [Data] = []
    private var isClosed = false
    private let incoming: AsyncStream<Data>
    private let feed: AsyncStream<Data>.Continuation
    private var iterator: AsyncStream<Data>.AsyncIterator

    init() {
        (incoming, feed) = AsyncStream<Data>.makeStream()
        iterator = incoming.makeAsyncIterator()
    }

    var sent: Data { lock.lock(); defer { lock.unlock() }; return sentData.reduce(Data(), +) }
    var closed: Bool { lock.lock(); defer { lock.unlock() }; return isClosed }

    /// The service on the Mac writes `data`.
    func deliver(_ data: Data) { feed.yield(data) }
    /// The service on the Mac closes its side.
    func end() { feed.finish() }

    func send(_ data: Data) async throws {
        lock.lock(); defer { lock.unlock() }
        sentData.append(data)
    }

    func receive() async throws -> Data? {
        var copy = iterator
        let next = await copy.next()
        iterator = copy
        return next
    }

    func close() {
        lock.lock()
        isClosed = true
        lock.unlock()
        feed.finish()
    }
}

/// Ports something listens on, each answering with a fresh socket the test can reach.
private final class FakeTunnelDialer: TunnelDialing, @unchecked Sendable {
    private let lock = NSLock()
    private let listening: Set<Int>
    private var sockets: [Int: FakeTunnelSocket] = [:]

    init(listening: Set<Int>) { self.listening = listening }

    func socket(_ port: Int) -> FakeTunnelSocket? { lock.lock(); defer { lock.unlock() }; return sockets[port] }

    func dial(port: Int) async throws -> TunnelSocket {
        guard listening.contains(port) else { throw TunnelUnavailable(port: port) }
        let socket = FakeTunnelSocket()
        lock.lock(); sockets[port] = socket; lock.unlock()
        return socket
    }
}

/// Waits up to two seconds for `check`.
private func eventually(_ what: String, _ check: () async -> Bool) async throws {
    for _ in 0..<200 {
        if await check() { return }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("Timed out waiting for \(what)")
}

private func openTunnel(_ session: Session, port: Int) async throws -> Envelope {
    try unwrapped(try await session.send(try .request(.tunnelOpen, body: TunnelOpenRequest(port: port))))
}

final class AgentTunnelTests: XCTestCase {
    func testPolicyAllowsOnlyWhatThePersonChose() throws {
        XCTAssertFalse(TunnelPolicy.off.allows(22))
        XCTAssertTrue(TunnelPolicy.sshOnly.allows(22))
        XCTAssertFalse(TunnelPolicy.sshOnly.allows(3000))
        let some = TunnelPolicy(mode: .sshAndPorts, ports: [3000, 5432, 3000, 0, 70_000])
        XCTAssertEqual(some.ports, [3000, 5432], "Duplicates and non-ports are dropped")
        XCTAssertTrue(some.allows(22) && some.allows(5432))
        XCTAssertFalse(some.allows(8080))
        XCTAssertTrue(TunnelPolicy(mode: .anyPort).allows(8080))
        XCTAssertFalse(TunnelPolicy(mode: .anyPort).allows(0))
        XCTAssertEqual(TunnelPolicy.parsePorts("3000, 5432 8080"), [3000, 5432, 8080])
        XCTAssertNil(TunnelPolicy.parsePorts("3000, ssh"))
        // Settings saved before tunnels keep them off.
        let old = try JSONDecoder().decode(RemoteSettings.self, from: Data(#"{"isEnabled":true,"allowActions":true,"allowFromAnywhere":true}"#.utf8))
        XCTAssertEqual(old.tunnels, .off)
        XCTAssertEqual(RemoteSettings().tunnels, .off)
        let saved = RemoteSettings(isEnabled: true, tunnels: some)
        XCTAssertEqual(try JSONDecoder().decode(RemoteSettings.self, from: JSONEncoder().encode(saved)).tunnels, some)
    }

    func testATunnelCarriesBytesBothWaysToAnAllowedPort() async throws {
        let dialer = FakeTunnelDialer(listening: [22, 3000])
        let harness = Harness(settings: RemoteSettings(isEnabled: true, allowActions: false, tunnels: .sshOnly), tunnelDialer: dialer)
        let account = Account()
        try await join(harness, account)
        let session = try await accountDevice(harness, account)

        let capabilities = try unwrapped(try await session.send(.request(.capabilities))).body(Capabilities.self)
        XCTAssertEqual(capabilities.tunnels, .sshOnly)
        XCTAssertTrue(capabilities.operations.contains(.tunnelOpen))

        // Not allowed, though something listens there; the connection stays usable.
        let refused = try await openTunnel(session, port: 3000)
        XCTAssertEqual(try refused.body(RemoteError.self).code, .notPermitted)

        let opened = try await openTunnel(session, port: 22).body(TunnelOpenResponse.self)
        XCTAssertEqual(opened.port, 22)
        let socket = try unwrapped(dialer.socket(22))

        // Console to Mac.
        await session.connection.receive(Framing.frame(try session.channel.seal(Data("SSH-2.0-client\r\n".utf8))))
        try await eventually("bytes on the Mac") { socket.sent == Data("SSH-2.0-client\r\n".utf8) }

        // Mac to console, sealed in order.
        socket.deliver(Data("SSH-2.0-OpenSSH_9.8\r\n".utf8))
        var received = Data()
        try await eventually("bytes at the console") {
            for frame in await session.outbox.takeRaw() { received += (try? session.channel.open(frame)) ?? Data() }
            return received == Data("SSH-2.0-OpenSSH_9.8\r\n".utf8)
        }

        let snapshot = await harness.state.snapshot()
        XCTAssertEqual(snapshot.tunnels.map(\.port), [22])
        XCTAssertEqual(snapshot.tunnels.first?.consoleName, "Laptop")
        XCTAssertEqual(snapshot.tunnels.first?.viaRelay, false)

        // Closed from the Mac: the socket and the connection end, and the log says so.
        await harness.state.closeTunnel(try unwrapped(snapshot.tunnels.first).id)
        XCTAssertTrue(socket.closed)
        let closed = await session.outbox.closed
        XCTAssertTrue(closed)
        let tunnels = await harness.state.snapshot().tunnels
        XCTAssertTrue(tunnels.isEmpty)
        let events = await harness.state.log.entries.map(\.event)
        XCTAssertTrue(events.contains("Open tunnel to port 3000"))
        XCTAssertTrue(events.contains("Opened tunnel to port 22"))
        XCTAssertTrue(events.contains("Closed tunnel to port 22"))
    }

    func testTheServiceClosingItsSideEndsTheTunnel() async throws {
        let dialer = FakeTunnelDialer(listening: [22])
        let harness = Harness(settings: RemoteSettings(isEnabled: true, tunnels: .sshOnly), tunnelDialer: dialer)
        let account = Account()
        try await join(harness, account)
        let session = try await accountDevice(harness, account)
        _ = try await openTunnel(session, port: 22).body(TunnelOpenResponse.self)
        try unwrapped(dialer.socket(22)).end()
        try await eventually("the connection to close") { await session.outbox.closed }
        // The console was told with an empty piece first.
        let last = try unwrapped(await session.outbox.takeRaw().last)
        XCTAssertEqual(try session.channel.open(last), Data())
    }

    func testViewersRelayStreamsWithoutTunnelsAndSwitchedOffMacsAreRefused() async throws {
        let dialer = FakeTunnelDialer(listening: [22])

        let viewOnly = Harness(settings: RemoteSettings(isEnabled: true, tunnels: .sshOnly), tunnelDialer: dialer), viewAccount = Account()
        try await join(viewOnly, viewAccount, roleCap: .viewOnly)
        let viewer = try await accountDevice(viewOnly, viewAccount)
        let viewerCapabilities = try unwrapped(try await viewer.send(.request(.capabilities))).body(Capabilities.self)
        XCTAssertEqual(viewerCapabilities.tunnels, .off)
        let viewerRefusal = try await openTunnel(viewer, port: 22).body(RemoteError.self)
        XCTAssertEqual(viewerRefusal.code, .notPermitted)

        let relayed = Harness(settings: RemoteSettings(isEnabled: true, tunnels: .sshOnly), tunnelDialer: dialer), relayAccount = Account()
        try await join(relayed, relayAccount)
        let plain = try await accountDevice(relayed, relayAccount, allowsTunnels: false)
        let plainCapabilities = try unwrapped(try await plain.send(.request(.capabilities))).body(Capabilities.self)
        XCTAssertEqual(plainCapabilities.tunnels, .sshOnly,
                       "What the person allows, so a console on the relay knows to open a tunnel stream; this stream itself carries none")
        let relayRefusal = try await openTunnel(plain, port: 22).body(RemoteError.self)
        XCTAssertEqual(relayRefusal.code, .notPermitted)
        XCTAssertTrue(relayRefusal.message.contains("Ultra"))

        let off = Harness(settings: RemoteSettings(isEnabled: true), tunnelDialer: dialer), offAccount = Account()
        try await join(off, offAccount)
        let device = try await accountDevice(off, offAccount)
        let offRefusal = try await openTunnel(device, port: 22).body(RemoteError.self)
        XCTAssertTrue(offRefusal.message.contains("turned off"))

        let nothing = Harness(settings: RemoteSettings(isEnabled: true, tunnels: TunnelPolicy(mode: .anyPort)), tunnelDialer: dialer)
        let nothingAccount = Account()
        try await join(nothing, nothingAccount)
        let other = try await accountDevice(nothing, nothingAccount)
        let unavailable = try await openTunnel(other, port: 9999).body(RemoteError.self)
        XCTAssertEqual(unavailable.code, .unavailable, "Nothing listens there")
    }

    func testLoweringTheAccountToViewOnlyClosesTunnels() async throws {
        let dialer = FakeTunnelDialer(listening: [22])
        let harness = Harness(settings: RemoteSettings(isEnabled: true, tunnels: .sshOnly), tunnelDialer: dialer)
        let account = Account()
        try await join(harness, account)
        let session = try await accountDevice(harness, account)
        _ = try await openTunnel(session, port: 22).body(TunnelOpenResponse.self)
        await harness.state.setWorkspaceRoleCap(.viewOnly)
        XCTAssertTrue(try unwrapped(dialer.socket(22)).closed)
        let closed = await session.outbox.closed
        XCTAssertTrue(closed)
        let tunnels = await harness.state.snapshot().tunnels
        XCTAssertTrue(tunnels.isEmpty)
    }

    func testTurningTunnelsOffClosesOpenOnes() async throws {
        let dialer = FakeTunnelDialer(listening: [22])
        let harness = Harness(settings: RemoteSettings(isEnabled: true, tunnels: .sshOnly), tunnelDialer: dialer)
        let account = Account()
        try await join(harness, account)
        let session = try await accountDevice(harness, account)
        _ = try await openTunnel(session, port: 22).body(TunnelOpenResponse.self)
        await harness.state.update(RemoteSettings(isEnabled: true, tunnels: .off))
        XCTAssertTrue(try unwrapped(dialer.socket(22)).closed)
        let closed = await session.outbox.closed
        XCTAssertTrue(closed)
        let events = await harness.state.log.entries.map(\.event)
        XCTAssertTrue(events.contains("Set Allow tunnels to Off"))
    }
}
