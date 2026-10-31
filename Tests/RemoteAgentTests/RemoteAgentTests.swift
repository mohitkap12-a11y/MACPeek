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
    private var consoles: [PairedConsole] = []
    private var log = ActivityLog()
    private var membership: WorkspaceMembership?

    private func locked<Value>(_ body: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    func loadConsoles() throws -> [PairedConsole] { locked { consoles } }
    func saveConsoles(_ consoles: [PairedConsole]) throws { locked { self.consoles = consoles } }
    func loadLog() throws -> ActivityLog { locked { log } }
    func saveLog(_ log: ActivityLog) throws { locked { self.log = log } }
    func loadMembership() throws -> WorkspaceMembership? { locked { membership } }
    func saveMembership(_ membership: WorkspaceMembership?) throws { locked { self.membership = membership } }
}

/// What the agent sent and whether it closed, collected from the transport side.
private actor Outbox {
    private var reader = Framing.Reader()
    private(set) var messages: [WireMessage] = []
    private(set) var closed = false

    func append(_ bytes: Data) throws {
        for frame in try reader.append(bytes) { messages.append(try WireMessage.decoded(from: frame)) }
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

    init(settings: RemoteSettings = RemoteSettings(isEnabled: true, allowActions: true)) {
        state = AgentState(identity: macIdentity, store: store, settings: settings)
        handler = RequestHandler(readers: readers(), actions: actions(counter), agentVersion: "0.3.0")
    }

    func connect() async -> (AgentConnection, Outbox) {
        let outbox = Outbox()
        let connection = AgentConnection(state: state, handler: handler, send: { try? await outbox.append($0) },
                                         onClose: { await outbox.markClosed() })
        await connection.start()
        return (connection, outbox)
    }
}

private func deliver(_ message: WireMessage, to connection: AgentConnection) async throws {
    await connection.receive(Framing.frame(try message.encoded()))
}

/// Pairs a console with the harness's Mac, both people confirming the words. Returns the console identity.
@discardableResult
private func pair(_ harness: Harness, role: ConsoleRole, name: String = "Laptop") async throws -> DeviceIdentity {
    try await pairReturningClaim(harness, role: role, identity: DeviceIdentity(name: name)).identity
}

/// Pairs, optionally offering a workspace grant; returns the claim the Mac sent back, if it joined.
private func pairReturningClaim(_ harness: Harness, role: ConsoleRole, identity consoleIdentity: DeviceIdentity,
                                grant: WorkspaceGrant? = nil) async throws -> (identity: DeviceIdentity, claim: MacClaim?) {
    let code = try unwrapped(await harness.state.newPairingCode())
    let (connection, outbox) = await harness.connect()
    var console = ConsolePairing(identity: consoleIdentity)
    try await deliver(.pairStart(console.start()), to: connection)
    guard case .pairAccept(let accept)? = await outbox.take().first else { throw Unreadable() }
    let (reveal, words) = try console.reveal(after: accept, code: code.digits)
    try await deliver(.pairReveal(reveal), to: connection)
    let pending = try unwrapped(await harness.state.pendingPairing)
    XCTAssertEqual(pending.words, words)
    try await deliver(.pairConfirm(console.confirm(grant: grant)), to: connection)
    let noConfirmYet = await outbox.take()
    XCTAssertTrue(noConfirmYet.isEmpty, "The Mac must not confirm before its own person has")
    await harness.state.resolvePairing(role: role)
    guard case .pairConfirm(let macConfirm)? = await outbox.take().first else { throw Unreadable() }
    let confirmed = try console.macConfirmation(from: macConfirm)
    XCTAssertEqual(confirmed.mac.signingKey, harness.macIdentity.publicIdentity.signingKey)
    await connection.disconnected()
    return (consoleIdentity, confirmed.claim)
}

/// A console session over the handshake, sending requests and reading responses.
private final class Session {
    let connection: AgentConnection
    let outbox: Outbox
    var channel: SecureChannel

    init(_ harness: Harness, identity: DeviceIdentity, chain: WorkspaceChain? = nil) async throws {
        (connection, outbox) = await harness.connect()
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

    func testFileStoreRoundTripsWithPrivatePermissions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileAgentStore(directory: directory)
        XCTAssertEqual(try store.loadConsoles(), [])
        let console = PairedConsole(identity: DeviceIdentity(name: "Laptop").publicIdentity, role: .viewOnly,
                                    pairedAt: Date(timeIntervalSince1970: 1_700_000_000))
        try store.saveConsoles([console])
        XCTAssertEqual(try store.loadConsoles(), [console])
        let path = directory.appendingPathComponent("paired-consoles.json").path
        let permissions = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
    }
}

final class AgentPairingTests: XCTestCase {
    func testPairingNeedsBothPeopleAndStoresTheRole() async throws {
        let harness = Harness()
        let console = try await pair(harness, role: .viewOnly)
        let consoles = await harness.state.consoles
        XCTAssertEqual(consoles.map(\.identity.signingKey), [console.publicIdentity.signingKey])
        XCTAssertEqual(consoles.first?.role, .viewOnly)
        let code = await harness.state.pairingCode
        XCTAssertNil(code, "A code works for one pairing only")
        let observed = await harness.state.log.isIntact
        XCTAssertTrue(observed)
    }

    func testNoPairingWithoutACodeOnScreen() async throws {
        let harness = Harness()
        let (connection, outbox) = await harness.connect()
        try await deliver(.pairStart(ConsolePairing(identity: DeviceIdentity(name: "Laptop")).start()), to: connection)
        guard case .refused? = await outbox.take().first else { return XCTFail("Expected a refusal") }
        let observed = await outbox.closed
        XCTAssertTrue(observed)
    }

    func testDecliningTheWordsPairsNothing() async throws {
        let harness = Harness()
        let code = try unwrapped(await harness.state.newPairingCode())
        let (connection, outbox) = await harness.connect()
        var console = ConsolePairing(identity: DeviceIdentity(name: "Laptop"))
        try await deliver(.pairStart(console.start()), to: connection)
        guard case .pairAccept(let accept)? = await outbox.take().first else { return XCTFail() }
        try await deliver(.pairReveal(try console.reveal(after: accept, code: code.digits).reveal), to: connection)
        try await deliver(.pairConfirm(console.confirm()), to: connection)
        await harness.state.resolvePairing(role: nil)
        guard case .refused? = await outbox.take().first else { return XCTFail("Expected a refusal") }
        let consoles = await harness.state.consoles
        XCTAssertTrue(consoles.isEmpty)
        let pending = await harness.state.pendingPairing
        XCTAssertNil(pending)
    }

    func testWrongCodesWithdrawTheCode() async throws {
        let harness = Harness()
        let code = try unwrapped(await harness.state.newPairingCode())
        let wrong = code.digits == "000000" ? "111111" : "000000"
        for _ in 0..<PairingCode.maximumAttempts {
            let (connection, outbox) = await harness.connect()
            var console = ConsolePairing(identity: DeviceIdentity(name: "Laptop"))
            try await deliver(.pairStart(console.start()), to: connection)
            guard case .pairAccept(let accept)? = await outbox.take().first else { return XCTFail() }
            try await deliver(.pairReveal(try console.reveal(after: accept, code: wrong).reveal), to: connection)
            guard case .refused? = await outbox.take().first else { return XCTFail("Expected a refusal") }
        }
        let remaining = await harness.state.pairingCode
        XCTAssertNil(remaining)
    }

    func testParallelConnectionsShareTheAttemptLimit() async throws {
        let harness = Harness()
        let code = try unwrapped(await harness.state.newPairingCode())
        let wrong = code.digits == "000000" ? "111111" : "000000"
        // Every connection starts pairing before any guess is checked, as an attacker trying many codes at once would.
        var started: [(AgentConnection, Outbox, ConsolePairing, PairingMessage.Accept)] = []
        for _ in 0...PairingCode.maximumAttempts {
            let (connection, outbox) = await harness.connect()
            let console = ConsolePairing(identity: DeviceIdentity(name: "Laptop"))
            try await deliver(.pairStart(console.start()), to: connection)
            guard case .pairAccept(let accept)? = await outbox.take().first else { return XCTFail() }
            started.append((connection, outbox, console, accept))
        }
        for (connection, outbox, var console, accept) in started.dropLast() {
            try await deliver(.pairReveal(try console.reveal(after: accept, code: wrong).reveal), to: connection)
            guard case .refused? = await outbox.take().first else { return XCTFail("Expected a refusal") }
        }
        // The code is withdrawn, so even the right code on a connection begun earlier no longer pairs.
        let (connection, outbox, _, accept) = try unwrapped(started.last)
        var console = try unwrapped(started.last).2
        try await deliver(.pairReveal(try console.reveal(after: accept, code: code.digits).reveal), to: connection)
        guard case .refused? = await outbox.take().first else { return XCTFail("Expected a refusal") }
        let pending = await harness.state.pendingPairing
        XCTAssertNil(pending)
    }

    func testBothConfirmationsArrivingTogetherPairOnce() async throws {
        // The console's Confirm and the decision on this Mac race; whichever finishes the pairing, it must succeed once.
        for _ in 0..<25 {
            let harness = Harness()
            let code = try unwrapped(await harness.state.newPairingCode())
            let (connection, outbox) = await harness.connect()
            var console = ConsolePairing(identity: DeviceIdentity(name: "Laptop"))
            try await deliver(.pairStart(console.start()), to: connection)
            guard case .pairAccept(let accept)? = await outbox.take().first else { return XCTFail() }
            try await deliver(.pairReveal(try console.reveal(after: accept, code: code.digits).reveal), to: connection)
            let confirm = try console.confirm()
            async let fromConsole: Void = deliver(.pairConfirm(confirm), to: connection)
            async let fromMac: Void = harness.state.resolvePairing(role: .viewOnly)
            _ = try await (fromConsole, fromMac)
            let messages = await outbox.take()
            XCTAssertEqual(messages.filter { if case .pairConfirm = $0 { return true } else { return false } }.count, 1, "\(messages)")
            XCTAssertFalse(messages.contains { if case .refused = $0 { return true } else { return false } }, "\(messages)")
            let consoles = await harness.state.consoles
            XCTAssertEqual(consoles.count, 1)
        }
    }

    func testTurningOffEndsAPairingAndRefusesNewConnections() async throws {
        let harness = Harness()
        _ = await harness.state.newPairingCode()
        let (connection, outbox) = await harness.connect()
        await harness.state.update(RemoteSettings(isEnabled: false))
        let observed = await outbox.closed
        XCTAssertTrue(observed)
        let code = await harness.state.pairingCode
        XCTAssertNil(code)
        let (late, lateOutbox) = await harness.connect()
        try await deliver(.hello(ConsoleHandshake(identity: DeviceIdentity(name: "Laptop")).hello()), to: late)
        guard case .refused? = await lateOutbox.take().first else { return XCTFail("Expected a refusal") }
        _ = connection
    }
}

final class AgentSessionTests: XCTestCase {
    func testPairedConsoleReadsOverAnEncryptedSession() async throws {
        let harness = Harness()
        let identity = try await pair(harness, role: .viewOnly)
        let session = try await Session(harness, identity: identity)

        let capabilities = try unwrapped(try await session.send(.request(.capabilities))).body(Capabilities.self)
        XCTAssertEqual(capabilities.device, device)
        XCTAssertEqual(capabilities.agentVersion, "0.3.0")
        XCTAssertFalse(capabilities.actionsAllowed, "View-only consoles may not act")

        let ports = try unwrapped(try await session.send(.request(.ports))).body([PortInfo].self)
        XCTAssertEqual(ports, [port])

        let failure = try unwrapped(try await session.send(.request(.memoryStats)))
        XCTAssertEqual(failure.kind, .error)
        XCTAssertEqual(try failure.body(RemoteError.self).code, .unavailable)

        let unknown = try unwrapped(try await session.send(.request("files.delete")))
        XCTAssertEqual(try unknown.body(RemoteError.self).code, .unknownOperation)
    }

    func testDNSProbesOnlyTheMacsOwnServers() async throws {
        let harness = Harness()
        let session = try await Session(harness, identity: try await pair(harness, role: .viewOnly))

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

    func testUnpairedConsoleIsRefused() async throws {
        let harness = Harness()
        try await pair(harness, role: .viewAndAct)
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

        let viewOnly = Harness()
        let viewer = try await Session(viewOnly, identity: try await pair(viewOnly, role: .viewOnly))
        let viewerCode = try unwrapped(try await viewer.send(request)).body(RemoteError.self).code
        XCTAssertEqual(viewerCode, .notPermitted)

        let switchedOff = Harness(settings: RemoteSettings(isEnabled: true, allowActions: false))
        let actor = try await Session(switchedOff, identity: try await pair(switchedOff, role: .viewAndAct))
        let switchedOffCode = try unwrapped(try await actor.send(request)).body(RemoteError.self).code
        XCTAssertEqual(switchedOffCode, .actionsDisabled)

        let allowed = Harness()
        let operator_ = try await Session(allowed, identity: try await pair(allowed, role: .viewAndAct))
        let allowedResult = try unwrapped(try await operator_.send(request)).body(ActionResult.self).result
        XCTAssertEqual(allowedResult, .terminated)

        let counts = (await viewOnly.counter.count, await switchedOff.counter.count, await allowed.counter.count)
        XCTAssertEqual(counts.0, 0)
        XCTAssertEqual(counts.1, 0)
        XCTAssertEqual(counts.2, 1)

        // Every action, refused or not, is in the log, attributed to the console.
        let entries = await allowed.state.log.entries
        XCTAssertEqual(entries.last?.actor, "Laptop")
        XCTAssertEqual(entries.last?.event, "Free port 3000 (node, PID 4242)")
        XCTAssertEqual(entries.last?.outcome, "Done")
        let refused = await viewOnly.state.log.entries.last
        XCTAssertEqual(refused?.outcome, "Refused: This console is paired view-only.")
    }

    func testRevokingEndsTheSession() async throws {
        let harness = Harness()
        let identity = try await pair(harness, role: .viewOnly)
        let session = try await Session(harness, identity: identity)
        await harness.state.revoke(identity.publicIdentity.signingKey)
        let observed = await session.outbox.closed
        XCTAssertTrue(observed)
        let afterRevoke = try await session.send(.request(.capabilities))
        XCTAssertNil(afterRevoke)
    }

    func testReplayedFrameEndsTheSession() async throws {
        let harness = Harness()
        let session = try await Session(harness, identity: try await pair(harness, role: .viewOnly))
        let frame = try session.channel.seal(JSONEncoder().encode(Envelope.request(.deviceInfo)))
        try await deliver(.sealed(frame), to: session.connection)
        _ = await session.outbox.take()
        try await deliver(.sealed(frame), to: session.connection)
        guard case .refused? = await session.outbox.take().first else { return XCTFail("Expected a refusal") }
        let observed = await session.outbox.closed
        XCTAssertTrue(observed)
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

final class AgentWorkspaceTests: XCTestCase {
    private func status(_ session: Session) async throws -> WorkspaceStatus {
        try unwrapped(try await session.send(.request(.workspaceStatus))).body(WorkspaceStatus.self)
    }

    func testPairingIntoAnAccountLetsEveryDeviceOfItIn() async throws {
        let harness = Harness(), account = Account()
        let laptop = DeviceIdentity(name: "Laptop"), studio = DeviceIdentity(name: "Desk")
        let paired = try await pairReturningClaim(harness, role: .viewAndAct, identity: laptop, grant: try account.grant(for: laptop))

        let claim = try unwrapped(paired.claim)
        XCTAssertTrue(claim.isValid)
        XCTAssertEqual(claim.workspaceID, account.id)
        XCTAssertEqual(claim.macKey, harness.macIdentity.publicIdentity.signingKey)
        let consoles = await harness.state.consoles
        XCTAssertTrue(consoles.isEmpty, "The account is pinned, not the console")
        let membership = try unwrapped(await harness.state.membership)
        XCTAssertEqual(membership.workspaceKey, account.publicKey)
        XCTAssertEqual(membership.roleCap, .viewAndAct)

        // Another device of the account, never paired here, connects with its chain.
        let session = try await Session(harness, identity: studio, chain: try account.chain(for: studio))
        let capabilities = try unwrapped(try await session.send(.request(.capabilities))).body(Capabilities.self)
        XCTAssertTrue(capabilities.actionsAllowed)
        XCTAssertEqual(capabilities.protocolVersion, 2)
        XCTAssertTrue(capabilities.operations.contains(.workspaceAdopt))
        let current = try await status(session)
        XCTAssertEqual(current.workspaceID, account.id)
        XCTAssertTrue(current.viaWorkspace)
        XCTAssertTrue(try unwrapped(current.claim).isValid)
        let devices = await harness.state.membership?.devices.map(\.identity.name)
        XCTAssertEqual(devices, ["Desk"])
    }

    func testViewersAndTheMacsChoiceLimitAccess() async throws {
        let harness = Harness(), account = Account()
        let laptop = DeviceIdentity(name: "Laptop")
        _ = try await pairReturningClaim(harness, role: .viewOnly, identity: laptop, grant: try account.grant(for: laptop))
        let owner = try await Session(harness, identity: laptop, chain: try account.chain(for: laptop))
        var capabilities = try unwrapped(try await owner.send(.request(.capabilities))).body(Capabilities.self)
        XCTAssertFalse(capabilities.actionsAllowed, "The Mac chose view only")

        await harness.state.setWorkspaceRoleCap(.viewAndAct)
        let viewer = DeviceIdentity(name: "Tablet")
        let session = try await Session(harness, identity: viewer, chain: try account.chain(for: viewer, role: .viewer))
        capabilities = try unwrapped(try await session.send(.request(.capabilities))).body(Capabilities.self)
        XCTAssertFalse(capabilities.actionsAllowed, "A viewer never acts")
        let freed = try unwrapped(try await session.send(try .request(.freePort, body: FreePortRequest(port: port))))
        XCTAssertEqual(freed.kind, .error)
        let count = await harness.counter.count
        XCTAssertEqual(count, 0)
    }

    func testStrangersAndOtherAccountsAreRefused() async throws {
        let harness = Harness(), account = Account()
        let laptop = DeviceIdentity(name: "Laptop")
        _ = try await pairReturningClaim(harness, role: .viewAndAct, identity: laptop, grant: try account.grant(for: laptop))
        let stranger = DeviceIdentity(name: "Stranger")
        let session = try await Session(harness, identity: stranger, chain: try Account().chain(for: stranger))
        let answer = try await session.send(.request(.capabilities))
        XCTAssertNil(answer)
        let closed = await session.outbox.closed
        XCTAssertTrue(closed)
    }

    func testRevocationEndsTheSessionAndOldListsAreIgnored() async throws {
        let harness = Harness(), account = Account()
        let laptop = DeviceIdentity(name: "Laptop"), lost = DeviceIdentity(name: "Lost")
        _ = try await pairReturningClaim(harness, role: .viewAndAct, identity: laptop, grant: try account.grant(for: laptop))
        let lostSession = try await Session(harness, identity: lost, chain: try account.chain(for: lost))
        let before = try await lostSession.send(.request(.capabilities))
        XCTAssertNotNil(before)

        let owner = try await Session(harness, identity: laptop, chain: try account.chain(for: laptop))
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

    func testMoveThisMacToAnAccountAndUndo() async throws {
        let harness = Harness(), account = Account()
        let console = try await pair(harness, role: .viewAndAct)
        let session = try await Session(harness, identity: console)
        let initial = try await status(session)
        XCTAssertNil(initial.workspaceID)

        let accountDevice = DeviceIdentity(name: "Laptop account key")
        let moved = try unwrapped(try await session.send(try .request(.workspaceAdopt, body: try account.grant(for: accountDevice))))
            .body(WorkspaceStatus.self)
        XCTAssertEqual(moved.workspaceID, account.id)
        XCTAssertTrue(try unwrapped(moved.claim).isValid)
        let membership = try unwrapped(await harness.state.membership)
        XCTAssertEqual(membership.roleCap, .viewAndAct, "The account gets the access this console had")
        XCTAssertEqual(membership.movedFrom?.identity.signingKey, console.publicIdentity.signingKey)
        var consoles = await harness.state.consoles
        XCTAssertTrue(consoles.isEmpty, "The console now comes in through the account")
        let logged = await harness.state.log.entries.last?.event
        XCTAssertEqual(logged, "Laptop moved this Mac to me@example.com's account")

        let viaAccount = try await Session(harness, identity: accountDevice, chain: try account.chain(for: accountDevice))
        let answered = try await viaAccount.send(.request(.capabilities))
        XCTAssertNotNil(answered)

        await harness.state.undoMove()
        consoles = await harness.state.consoles
        XCTAssertEqual(consoles.map(\.identity.signingKey), [console.publicIdentity.signingKey])
        let left = await harness.state.membership
        XCTAssertNil(left)
        let closed = await viaAccount.outbox.closed
        XCTAssertTrue(closed)
    }

    func testAMacInAnotherAccountIsNotMovedOverTheNetwork() async throws {
        let harness = Harness(), first = Account(), second = Account()
        let laptop = DeviceIdentity(name: "Laptop")
        _ = try await pairReturningClaim(harness, role: .viewAndAct, identity: laptop, grant: try first.grant(for: laptop))
        let console = try await pair(harness, role: .viewAndAct, name: "Old console")
        // Pairing on its own again does not take the Mac out of its account.
        let stillMember = await harness.state.membership
        XCTAssertNotNil(stillMember)
        let session = try await Session(harness, identity: console)
        let refused = try unwrapped(try await session.send(try .request(.workspaceAdopt, body: try second.grant(for: laptop))))
        XCTAssertEqual(refused.kind, .error)
        let workspaceID = await harness.state.membership?.workspaceID
        XCTAssertEqual(workspaceID, first.id)
    }

    func testLeavingTheAccountRefusesItsDevices() async throws {
        let harness = Harness(), account = Account()
        let laptop = DeviceIdentity(name: "Laptop")
        _ = try await pairReturningClaim(harness, role: .viewAndAct, identity: laptop, grant: try account.grant(for: laptop))
        let session = try await Session(harness, identity: laptop, chain: try account.chain(for: laptop))
        let answered = try await session.send(.request(.capabilities))
        XCTAssertNotNil(answered)
        await harness.state.leaveWorkspace()
        let closed = await session.outbox.closed
        XCTAssertTrue(closed)
        let again = try await Session(harness, identity: laptop, chain: try account.chain(for: laptop))
        let refused = try await again.send(.request(.capabilities))
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
