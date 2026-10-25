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

final class PairingCodeTests: XCTestCase {
    func testGeneratedCodesAreSixDigitsAndExpire() {
        let now = Date(timeIntervalSince1970: 1_761_000_000)
        let code = PairingCode.generate(now: now)
        XCTAssertEqual(code.digits.count, 6)
        XCTAssertTrue(code.digits.allSatisfy(\.isNumber))
        XCTAssertFalse(code.isExpired(at: now.addingTimeInterval(299)))
        XCTAssertTrue(code.isExpired(at: now.addingTimeInterval(300)))
        XCTAssertEqual(PairingCode(digits: "482913", expiresAt: now).formatted, "482 913")
    }

    func testTypedCodesAreNormalised() {
        XCTAssertEqual(PairingCode.normalized(" 482 913 "), "482913")
        XCTAssertEqual(PairingCode.normalized("482-913"), "482913")
        XCTAssertNil(PairingCode.normalized("48291"))
        XCTAssertNil(PairingCode.normalized("48291a"))
        XCTAssertNil(PairingCode.normalized("４８２９１３"))
    }

    func testWordListHasOneDistinctWordPerByte() {
        XCTAssertEqual(MatchingWords.list.count, 256)
        XCTAssertEqual(Set(MatchingWords.list).count, 256)
        XCTAssertEqual(MatchingWords.words(for: Data([0, 255, 1, 2, 9])), ["acorn", "dune", "actor", "album"])
    }
}

final class PairingTests: XCTestCase {
    private let now = Date()
    private let console = DeviceIdentity(name: "Console")
    private let mac = DeviceIdentity(name: "Mac")

    private func code(_ digits: String = "482913") -> PairingCode {
        PairingCode(digits: digits, expiresAt: now.addingTimeInterval(300))
    }

    func testSuccessfulPairingShowsTheSameWordsAndPinsBothIdentities() throws {
        var consoleSide = ConsolePairing(identity: console)
        var macSide = MacPairing(identity: mac, code: code())
        let accept = try macSide.accept(consoleSide.start(), now: now)
        let (reveal, consoleWords) = try consoleSide.reveal(after: accept, code: "482 913")
        let macWords = try macSide.words(after: reveal, now: now)
        XCTAssertEqual(consoleWords, macWords)
        XCTAssertEqual(consoleWords.count, 4)

        XCTAssertEqual(try macSide.consoleIdentity(from: consoleSide.confirm()), console.publicIdentity)
        XCTAssertEqual(try consoleSide.macIdentity(from: macSide.confirm()), mac.publicIdentity)
    }

    func testWrongCodeIsRefused() throws {
        var consoleSide = ConsolePairing(identity: console)
        var macSide = MacPairing(identity: mac, code: code())
        let accept = try macSide.accept(consoleSide.start(), now: now)
        let (reveal, _) = try consoleSide.reveal(after: accept, code: "482914")
        XCTAssertThrowsError(try macSide.words(after: reveal, now: now)) { XCTAssertEqual($0 as? PairingError, .wrongCode) }
        XCTAssertThrowsError(try macSide.confirm())
    }

    func testExpiredCodeIsRefused() throws {
        let consoleSide = ConsolePairing(identity: console)
        var macSide = MacPairing(identity: mac, code: PairingCode(digits: "482913", expiresAt: now))
        XCTAssertThrowsError(try macSide.accept(consoleSide.start(), now: now)) { XCTAssertEqual($0 as? PairingError, .codeExpired) }
    }

    func testRevealThatDoesNotMatchTheCommitmentIsRefused() throws {
        var consoleSide = ConsolePairing(identity: console)
        var otherConsole = ConsolePairing(identity: console)
        var macSide = MacPairing(identity: mac, code: code())
        let accept = try macSide.accept(consoleSide.start(), now: now)
        // A different key than the one committed to (what an attacker choosing keys after seeing the Mac's would send).
        let (swapped, _) = try otherConsole.reveal(after: accept, code: "482913")
        XCTAssertThrowsError(try macSide.words(after: swapped, now: now)) { XCTAssertEqual($0 as? PairingError, .commitmentMismatch) }
        _ = try consoleSide.reveal(after: accept, code: "482913")
    }

    func testPersonInTheMiddleSeesDifferentWords() throws {
        // The attacker pairs with the console pretending to be the Mac, and with the Mac pretending to be the console.
        var consoleSide = ConsolePairing(identity: console)
        var attackerAsMac = MacPairing(identity: DeviceIdentity(name: "Mac"), code: code())
        var attackerAsConsole = ConsolePairing(identity: DeviceIdentity(name: "Console"))
        var macSide = MacPairing(identity: mac, code: code())

        let (_, consoleWords) = try consoleSide.reveal(after: try attackerAsMac.accept(consoleSide.start(), now: now), code: "482913")
        let (reveal, _) = try attackerAsConsole.reveal(after: try macSide.accept(attackerAsConsole.start(), now: now), code: "482913")
        let macWords = try macSide.words(after: reveal, now: now)
        XCTAssertNotEqual(consoleWords, macWords)
    }

    func testConfirmFromAnotherSessionIsRefused() throws {
        func paired() throws -> (ConsolePairing, MacPairing) {
            var consoleSide = ConsolePairing(identity: console)
            var macSide = MacPairing(identity: mac, code: code())
            let (reveal, _) = try consoleSide.reveal(after: try macSide.accept(consoleSide.start(), now: now), code: "482913")
            _ = try macSide.words(after: reveal, now: now)
            return (consoleSide, macSide)
        }
        let (consoleA, _) = try paired()
        let (_, macB) = try paired()
        XCTAssertThrowsError(try macB.consoleIdentity(from: consoleA.confirm())) { XCTAssertEqual($0 as? PairingError, .invalidIdentity) }
    }

    func testMessagesOutOfOrderAreRefused() throws {
        var macSide = MacPairing(identity: mac, code: code())
        let consoleSide = ConsolePairing(identity: console)
        let start = consoleSide.start()
        _ = try macSide.accept(start, now: now)
        XCTAssertThrowsError(try macSide.accept(start, now: now)) { XCTAssertEqual($0 as? PairingError, .unexpectedMessage) }
        XCTAssertThrowsError(try consoleSide.confirm()) { XCTAssertEqual($0 as? PairingError, .unexpectedMessage) }
    }

    func testUnsupportedVersionIsRefused() {
        var macSide = MacPairing(identity: mac, code: code())
        let start = PairingMessage.Start(version: 99, commitment: Data(count: 32))
        XCTAssertThrowsError(try macSide.accept(start, now: now)) { XCTAssertEqual($0 as? PairingError, .unsupportedVersion(99)) }
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
