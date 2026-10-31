import XCTest
@testable import RemoteCrypto

/// A workspace with an owner and one device, built the way MacPeek Remote builds it.
struct TestWorkspace {
    let id = "ws_test"
    let key = WorkspaceKeys.newPrivateKey()
    let memberKey = WorkspaceKeys.newPrivateKey()
    let device = DeviceIdentity(name: "Laptop")

    var publicKey: Data { try! WorkspaceKeys.publicKey(of: key) }

    func member(_ role: WorkspaceRole = .owner, id memberID: String = "m_owner", key signingKey: Data? = nil,
                issuer: Data? = nil) throws -> MemberCertificate {
        try MemberCertificate.issue(workspaceID: id, memberID: memberID,
                                    signingKey: signingKey ?? WorkspaceKeys.publicKey(of: memberKey), role: role,
                                    issuedAt: 1_700_000_000_000, issuerPrivateKey: issuer ?? key)
    }

    func deviceCertificate(for identity: DeviceIdentity? = nil, memberID: String = "m_owner", memberPrivateKey: Data? = nil) throws
        -> DeviceCertificate {
        let identity = identity ?? device
        return try DeviceCertificate.issue(workspaceID: id, memberID: memberID, deviceID: "d_\(identity.name)",
                                           signingKey: identity.publicIdentity.signingKey, name: identity.name,
                                           issuedAt: 1_700_000_000_000, memberPrivateKey: memberPrivateKey ?? memberKey)
    }

    func chain(_ role: WorkspaceRole = .owner, for identity: DeviceIdentity? = nil) throws -> WorkspaceChain {
        WorkspaceChain(members: [try member(role)], device: try deviceCertificate(for: identity))
    }

    func grant(for identity: DeviceIdentity? = nil) throws -> WorkspaceGrant {
        WorkspaceGrant(workspaceID: id, workspaceKey: publicKey, name: "me@example.com", chain: try chain(for: identity))
    }

    func revocations(_ sequence: Int, _ keys: [Data]) throws -> RevocationList {
        try RevocationList.issue(workspaceID: id, sequence: sequence, revokedKeys: keys, workspacePrivateKey: key)
    }
}

final class WorkspaceTests: XCTestCase {
    func testChainVerifiesAndReturnsTheMemberRole() throws {
        let workspace = TestWorkspace()
        let chain = try workspace.chain(.member)
        XCTAssertEqual(try chain.verify(workspaceID: workspace.id, workspaceKey: workspace.publicKey,
                                        deviceKey: workspace.device.publicIdentity.signingKey), .member)
    }

    func testChainRefusesAnotherWorkspaceOrDevice() throws {
        let workspace = TestWorkspace(), other = TestWorkspace()
        let chain = try workspace.chain()
        let deviceKey = workspace.device.publicIdentity.signingKey
        XCTAssertThrowsError(try chain.verify(workspaceID: workspace.id, workspaceKey: other.publicKey, deviceKey: deviceKey)) {
            XCTAssertEqual($0 as? WorkspaceError, .invalidSignature)
        }
        XCTAssertThrowsError(try chain.verify(workspaceID: "ws_other", workspaceKey: workspace.publicKey, deviceKey: deviceKey)) {
            XCTAssertEqual($0 as? WorkspaceError, .wrongWorkspace)
        }
        XCTAssertThrowsError(try chain.verify(workspaceID: workspace.id, workspaceKey: workspace.publicKey,
                                              deviceKey: DeviceIdentity(name: "Thief").publicIdentity.signingKey)) {
            XCTAssertEqual($0 as? WorkspaceError, .wrongDevice)
        }
        // A device certificate signed by a key the workspace never certified.
        let forged = WorkspaceChain(members: [try workspace.member()],
                                    device: try workspace.deviceCertificate(memberPrivateKey: WorkspaceKeys.newPrivateKey()))
        XCTAssertThrowsError(try forged.verify(workspaceID: workspace.id, workspaceKey: workspace.publicKey, deviceKey: deviceKey))
    }

    func testRevokedDeviceOrMemberIsRefused() throws {
        let workspace = TestWorkspace()
        let chain = try workspace.chain()
        let deviceKey = workspace.device.publicIdentity.signingKey
        for revoked in [deviceKey, try WorkspaceKeys.publicKey(of: workspace.memberKey)] {
            XCTAssertThrowsError(try chain.verify(workspaceID: workspace.id, workspaceKey: workspace.publicKey, deviceKey: deviceKey,
                                                  revoked: [revoked])) {
                XCTAssertEqual($0 as? WorkspaceError, .revoked)
            }
        }
    }

    func testAdminsCertifyMembersButNotOwners() throws {
        let workspace = TestWorkspace()
        let adminKey = WorkspaceKeys.newPrivateKey(), memberKey = WorkspaceKeys.newPrivateKey()
        let admin = try workspace.member(.admin, id: "m_admin", key: WorkspaceKeys.publicKey(of: adminKey))
        let deviceKey = workspace.device.publicIdentity.signingKey
        func chain(_ role: WorkspaceRole, issuer: MemberCertificate) throws -> WorkspaceChain {
            let member = try workspace.member(role, id: "m_new", key: WorkspaceKeys.publicKey(of: memberKey), issuer: adminKey)
            return WorkspaceChain(members: [issuer, member],
                                  device: try workspace.deviceCertificate(memberID: "m_new", memberPrivateKey: memberKey))
        }
        XCTAssertEqual(try chain(.viewer, issuer: admin).verify(workspaceID: workspace.id, workspaceKey: workspace.publicKey,
                                                                deviceKey: deviceKey), .viewer)
        XCTAssertThrowsError(try chain(.owner, issuer: admin).verify(workspaceID: workspace.id, workspaceKey: workspace.publicKey,
                                                                     deviceKey: deviceKey)) {
            XCTAssertEqual($0 as? WorkspaceError, .issuerMayNotCertify)
        }
        let plainMember = try workspace.member(.member, id: "m_admin", key: WorkspaceKeys.publicKey(of: adminKey))
        XCTAssertThrowsError(try chain(.viewer, issuer: plainMember).verify(workspaceID: workspace.id,
                                                                            workspaceKey: workspace.publicKey, deviceKey: deviceKey)) {
            XCTAssertEqual($0 as? WorkspaceError, .issuerMayNotCertify)
        }
        let long = WorkspaceChain(members: [admin, admin, admin], device: try workspace.deviceCertificate())
        XCTAssertThrowsError(try long.verify(workspaceID: workspace.id, workspaceKey: workspace.publicKey, deviceKey: deviceKey)) {
            XCTAssertEqual($0 as? WorkspaceError, .chainTooLong)
        }
    }

    func testMessagesHaveOneReading() throws {
        let key = Data(repeating: 1, count: 32)
        XCTAssertEqual(try MemberCertificate.message(workspaceID: "ws_test", memberID: "m1", signingKey: key, role: .owner,
                                                     issuedAt: 1_700_000_000_000),
                       "macpeek-member-v1\nws_test\nm1\n\(key.base64EncodedString())\nowner\n1700000000000")
        XCTAssertThrowsError(try MemberCertificate.message(workspaceID: "ws\nx", memberID: "m1", signingKey: key, role: .owner,
                                                           issuedAt: 0)) {
            XCTAssertEqual($0 as? WorkspaceError, .invalidField)
        }
        let device = try DeviceCertificate.issue(workspaceID: "ws_test", memberID: "m1", deviceID: "d1", signingKey: key,
                                                 name: "Studio\nMac", issuedAt: 1, memberPrivateKey: WorkspaceKeys.newPrivateKey())
        XCTAssertEqual(device.name, "Studio Mac")
    }

    func testRevocationListsAreSignedAndOrdered() throws {
        let workspace = TestWorkspace()
        let list = try workspace.revocations(2, [Data(repeating: 2, count: 32), Data(repeating: 1, count: 32)])
        XCTAssertTrue(list.isValid(workspaceID: workspace.id, workspaceKey: workspace.publicKey))
        XCTAssertFalse(list.isValid(workspaceID: workspace.id, workspaceKey: TestWorkspace().publicKey))
        let shorter = RevocationList(workspaceID: list.workspaceID, sequence: list.sequence, revokedKeys: [list.revokedKeys[0]],
                                     signature: list.signature)
        XCTAssertFalse(shorter.isValid(workspaceID: workspace.id, workspaceKey: workspace.publicKey))
        let replayed = RevocationList(workspaceID: list.workspaceID, sequence: 3, revokedKeys: list.revokedKeys,
                                      signature: list.signature)
        XCTAssertFalse(replayed.isValid(workspaceID: workspace.id, workspaceKey: workspace.publicKey))
    }

    /// Signed with Node's Ed25519 (deterministic) from a private key of 32 bytes of 7; cloud/test checks the same values.
    func testSharedVectors() throws {
        let macKey = try XCTUnwrap(Data(base64Encoded: "6kpsY+KcUgq+9VB7Ey7F+ZVHdq6+vnuSQh7qaRRG0iw="))
        XCTAssertEqual(try WorkspaceKeys.publicKey(of: Data(repeating: 7, count: 32)), macKey)
        let claim = MacClaim(macKey: macKey, workspaceID: "ws_test", time: 1_700_000_000_000,
                             signature: try XCTUnwrap(Data(base64Encoded:
                                "pYygC3Z7VsMk34MaowUaS3/vmFyP4QkEKt2PCTV1n43yw0+A7GppQOM2KREQR0ZYa0bEvKcJP3zn5NwN+CgJAw==")))
        XCTAssertTrue(claim.isValid)
        XCTAssertFalse(MacClaim(macKey: macKey, workspaceID: "ws_other", time: claim.time, signature: claim.signature).isValid)
        let list = RevocationList(workspaceID: "ws_test", sequence: 3,
                                  revokedKeys: [Data(repeating: 1, count: 32), Data(repeating: 2, count: 32)],
                                  signature: try XCTUnwrap(Data(base64Encoded:
                                    "FGY2vzNieXMKoiNxjppuE7AaS4SFY5w+FdSF1uUHUKyzCxoWsQbxRRiJh0DW0gWFF9VdkjLZ9haCbKIP0fGyBw==")))
        XCTAssertTrue(list.isValid(workspaceID: "ws_test", workspaceKey: macKey))
    }

    func testClaimsAreTheMacsOwn() throws {
        let mac = DeviceIdentity(name: "Studio")
        let claim = try MacClaim.sign(by: mac, workspaceID: "ws_test", time: 1)
        XCTAssertTrue(claim.isValid)
        XCTAssertEqual(claim.macKey, mac.publicIdentity.signingKey)
        XCTAssertFalse(MacClaim(macKey: claim.macKey, workspaceID: "ws_test", time: 2, signature: claim.signature).isValid)
    }

    func testPairingCarriesTheGrantAndTheClaim() throws {
        let workspace = TestWorkspace()
        let code = PairingCode.generate()
        var console = ConsolePairing(identity: DeviceIdentity(name: "Laptop"))
        let mac = DeviceIdentity(name: "Studio")
        var macSide = MacPairing(identity: mac, code: code)
        let accept = try macSide.accept(console.start())
        let (reveal, _) = try console.reveal(after: accept, code: code.digits)
        _ = try macSide.words(after: reveal)

        let grant = try workspace.grant()
        let received = try macSide.consoleConfirmation(from: try console.confirm(grant: grant))
        XCTAssertEqual(received.grant, grant)
        let claim = try MacClaim.sign(by: mac, workspaceID: workspace.id, time: 5)
        let confirmed = try console.macConfirmation(from: try macSide.confirm(claim: claim))
        XCTAssertEqual(confirmed.claim, claim)
        XCTAssertNil(try console.macConfirmation(from: try macSide.confirm()).claim, "No claim from a Mac that did not join")

        // A claim signed by another key is dropped rather than trusted.
        let foreign = try MacClaim.sign(by: DeviceIdentity(name: "Other"), workspaceID: workspace.id, time: 5)
        XCTAssertNil(try console.macConfirmation(from: try macSide.confirm(claim: foreign)).claim)
        // An inconsistent grant is dropped: the Mac then pairs the console on its own.
        let broken = WorkspaceGrant(workspaceID: workspace.id, workspaceKey: TestWorkspace().publicKey, name: "x",
                                    chain: grant.chain)
        XCTAssertNil(try macSide.consoleConfirmation(from: try console.confirm(grant: broken)).grant)
    }

    func testHandshakeCarriesTheChain() throws {
        let workspace = TestWorkspace()
        let chain = try workspace.chain()
        let mac = DeviceIdentity(name: "Studio")
        var console = ConsoleHandshake(identity: workspace.device, chain: chain)
        var macSide = MacHandshake(identity: mac)
        let reply = try macSide.reply(to: console.hello())
        let finished = try console.finish(after: reply) { $0.isSameDevice(as: mac.publicIdentity) }
        var seen: WorkspaceChain?
        let accepted = try macSide.accept(finished.finish, trustChain: { identity, chain -> Bool in
            seen = chain
            return identity.isSameDevice(as: workspace.device.publicIdentity)
        })
        XCTAssertEqual(seen, chain)
        XCTAssertEqual(accepted.chain, chain)
        XCTAssertEqual(accepted.console.signingKey, workspace.device.publicIdentity.signingKey)
    }
}
