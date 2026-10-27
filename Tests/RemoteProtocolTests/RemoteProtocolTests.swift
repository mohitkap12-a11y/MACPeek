import XCTest
import MacPeekCore
import PortPeekKit
import ProcessPeekKit
import RemoteCrypto
@testable import RemoteProtocol

final class EnvelopeTests: XCTestCase {
    func testRequestResponseAndErrorKeepTheRequestId() throws {
        let request = Envelope.request(.memoryStats, id: "r1")
        let response = try request.response(["ok": true])
        XCTAssertEqual(response.id, "r1")
        XCTAssertEqual(response.kind, .response)
        XCTAssertEqual(try response.body([String: Bool].self), ["ok": true])

        let failure = request.failure(RemoteError(.unavailable, "no"))
        XCTAssertEqual(failure.kind, .error)
        XCTAssertEqual(try failure.body(RemoteError.self), RemoteError(.unavailable, "no"))
    }

    func testMissingOrWrongBodyIsAnInvalidPayloadError() {
        XCTAssertThrowsError(try Envelope.request(.freePort).body(FreePortRequest.self)) {
            XCTAssertEqual(($0 as? RemoteError)?.code, .invalidPayload)
        }
    }

    func testActionRequestsRoundTrip() throws {
        let port = PortInfo(port: 3000, protocolType: .tcp, address: "*", processName: "node", pid: 48213, user: "me",
                            state: .listen, startTime: 1_761_000_000)
        let request = try Envelope.request(.freePort, body: FreePortRequest(port: port), id: "a1")
        let decoded = try JSONDecoder().decode(Envelope.self, from: try JSONEncoder().encode(request))
        XCTAssertEqual(try decoded.body(FreePortRequest.self), FreePortRequest(port: port))
        XCTAssertTrue(decoded.operation.isAction)
        XCTAssertFalse(Operation.cpuSnapshot.isAction)
    }

    func testUnknownOperationsStillDecode() throws {
        let envelope = Envelope.request("gpu.snapshot", id: "x")
        let decoded = try JSONDecoder().decode(Envelope.self, from: try JSONEncoder().encode(envelope))
        XCTAssertEqual(decoded.operation.rawValue, "gpu.snapshot")
        XCTAssertFalse(Operation.reads.contains(decoded.operation))
    }
}

final class WireTests: XCTestCase {
    func testWireMessagesRoundTrip() throws {
        let messages: [WireMessage] = [
            .hello(ConsoleHandshake(identity: DeviceIdentity(name: "C")).hello()),
            .pairStart(ConsolePairing(identity: DeviceIdentity(name: "C")).start()),
            .sealed(Data([1, 2, 3])),
            .refused("Remote management is off"),
        ]
        for message in messages { XCTAssertEqual(try WireMessage.decoded(from: message.encoded()), message) }
    }

    func testFramesSurviveArbitraryChunking() throws {
        let payloads = [Data("one".utf8), Data(), Data(repeating: 7, count: 70_000)]
        let stream = payloads.map(Framing.frame).reduce(Data(), +)
        for chunk in [1, 3, 4096, stream.count] {
            var reader = Framing.Reader()
            var frames: [Data] = []
            var offset = 0
            while offset < stream.count {
                let end = min(offset + chunk, stream.count)
                frames += try reader.append(stream.subdata(in: offset..<end))
                offset = end
            }
            XCTAssertEqual(frames, payloads, "chunk \(chunk)")
        }
    }

    func testOversizedFrameIsRefusedBeforeBuffering() {
        var reader = Framing.Reader()
        let header = withUnsafeBytes(of: UInt32(Framing.maximumFrameSize + 1).bigEndian) { Data($0) }
        XCTAssertThrowsError(try reader.append(header)) {
            XCTAssertEqual($0 as? Framing.Error, .frameTooLarge(Framing.maximumFrameSize + 1))
        }
    }

    func testCapabilitiesRoundTrip() throws {
        let capabilities = Capabilities(agentVersion: "0.2.0",
                                        device: DeviceInfo(computerName: "Studio", localHostName: "Studio", modelIdentifier: "Mac16,7",
                                                           macOSVersion: "26.1", bootTime: Date(timeIntervalSince1970: 1)),
                                        operations: Operation.reads, actionsAllowed: false)
        XCTAssertEqual(try JSONDecoder().decode(Capabilities.self, from: try JSONEncoder().encode(capabilities)), capabilities)
    }
}
