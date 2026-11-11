import XCTest
@testable import RemoteCrypto

final class IdentityTests: XCTestCase {
    func testSignaturesVerifyOnlyForTheSignedDataAndKey() throws {
        let alice = DeviceIdentity(name: "Alice"), bob = DeviceIdentity(name: "Bob")
        let signature = try alice.signature(for: Data("hello".utf8))
        XCTAssertTrue(alice.publicIdentity.isValidSignature(signature, for: Data("hello".utf8)))
        XCTAssertFalse(alice.publicIdentity.isValidSignature(signature, for: Data("hellp".utf8)))
        XCTAssertFalse(bob.publicIdentity.isValidSignature(signature, for: Data("hello".utf8)))
    }

    func testStoredIdentityKeepsItsKey() throws {
        let original = DeviceIdentity(name: "Mac")
        let restored = try DeviceIdentity(name: "Mac", privateKeyData: original.privateKeyData)
        XCTAssertEqual(restored.publicIdentity, original.publicIdentity)
        XCTAssertThrowsError(try DeviceIdentity(name: "Mac", privateKeyData: Data([1, 2, 3])))
    }

    func testFingerprintIsFourGroupsAndIgnoresTheName() {
        let identity = DeviceIdentity(name: "Mac").publicIdentity
        XCTAssertEqual(identity.fingerprint.split(separator: " ").map(\.count), [4, 4, 4, 4])
        let renamed = PublicIdentity(signingKey: identity.signingKey, name: "Other")
        XCTAssertEqual(renamed.fingerprint, identity.fingerprint)
        XCTAssertTrue(renamed.isSameDevice(as: identity))
    }
}

final class AccountJoinTests: XCTestCase {
    func testTheRequestIsSignedByTheMacOnOneLine() throws {
        let mac = DeviceIdentity(name: "Studio")
        let key = mac.publicIdentity.signingKey
        XCTAssertEqual(try AccountJoin.requestMessage(macKey: key, name: "Office Mac", time: 1),
                       "macpeek-join-request-v1\n\(key.base64EncodedString())\nOffice Mac\n1")
        let signature = try AccountJoin.request(by: mac, name: "Office Mac", time: 1)
        XCTAssertTrue(mac.publicIdentity.isValidSignature(signature, for: Data(try AccountJoin.requestMessage(macKey: key, name: "Office Mac", time: 1).utf8)))
        XCTAssertThrowsError(try AccountJoin.requestMessage(macKey: key, name: "Two\nlines", time: 1))
    }
}

final class SessionTests: XCTestCase {
    private let console = DeviceIdentity(name: "Console")
    private let mac = DeviceIdentity(name: "Mac")

    private func connect(consoleTrusts: @escaping (PublicIdentity) -> Bool = { _ in true },
                         macTrusts: @escaping (PublicIdentity) -> Bool = { _ in true }) throws -> (SecureChannel, SecureChannel) {
        var consoleSide = ConsoleHandshake(identity: console)
        var macSide = MacHandshake(identity: mac)
        let reply = try macSide.reply(to: consoleSide.hello())
        let (finish, consoleChannel, seenMac) = try consoleSide.finish(after: reply, trust: consoleTrusts)
        XCTAssertEqual(seenMac, mac.publicIdentity)
        let (macChannel, seenConsole) = try macSide.accept(finish, trust: macTrusts)
        XCTAssertEqual(seenConsole, console.publicIdentity)
        return (consoleChannel, macChannel)
    }

    func testFramesFlowBothWays() throws {
        var (consoleChannel, macChannel) = try connect()
        for text in ["one", "two", ""] {
            XCTAssertEqual(try macChannel.open(try consoleChannel.seal(Data(text.utf8))), Data(text.utf8))
        }
        XCTAssertEqual(try consoleChannel.open(try macChannel.seal(Data("back".utf8))), Data("back".utf8))
    }

    func testEncryptedFramesHideThePlaintext() throws {
        var (consoleChannel, _) = try connect()
        let frame = try consoleChannel.seal(Data("port 3000 node".utf8))
        XCTAssertNil(frame.range(of: Data("node".utf8)))
    }

    func testTamperedReplayedAndReorderedFramesAreRejected() throws {
        var (consoleChannel, macChannel) = try connect()
        let first = try consoleChannel.seal(Data("first".utf8))
        let second = try consoleChannel.seal(Data("second".utf8))

        var tampered = first
        tampered[0] ^= 1
        XCTAssertThrowsError(try macChannel.open(tampered))
        XCTAssertThrowsError(try macChannel.open(second))  // out of order
        XCTAssertEqual(try macChannel.open(first), Data("first".utf8))
        XCTAssertThrowsError(try macChannel.open(first))  // replay
        XCTAssertEqual(try macChannel.open(second), Data("second".utf8))
    }

    func testUnpinnedMacIsRefusedByTheConsole() {
        XCTAssertThrowsError(try connect(consoleTrusts: { _ in false })) { XCTAssertEqual($0 as? SessionError, .untrustedPeer) }
    }

    func testUnpairedConsoleIsRefusedByTheMac() {
        XCTAssertThrowsError(try connect(macTrusts: { _ in false })) { XCTAssertEqual($0 as? SessionError, .untrustedPeer) }
    }

    func testReplyFromAnotherHandshakeIsRefused() throws {
        var consoleSide = ConsoleHandshake(identity: console)
        var macSide = MacHandshake(identity: mac)
        // The Mac answered a different console's Hello, so its signature is over a transcript this console never saw.
        let reply = try macSide.reply(to: ConsoleHandshake(identity: console).hello())
        XCTAssertThrowsError(try consoleSide.finish(after: reply, trust: { _ in true }))
    }

    func testUnsupportedVersionIsRefused() {
        var macSide = MacHandshake(identity: mac)
        let hello = HandshakeMessage.Hello(version: 2, ephemeralKey: ConsoleHandshake(identity: console).hello().ephemeralKey)
        XCTAssertThrowsError(try macSide.reply(to: hello)) { XCTAssertEqual($0 as? SessionError, .unsupportedVersion(2)) }
    }
}
