import XCTest
@testable import NetPeekKit
import MacPeekCore

final class NetExtrasTests: XCTestCase {
    func testProxyWithExceptionsAndScopedSectionIgnored() throws {
        let proxy = try XCTUnwrap(ProxyParser.parse(try fixture("scutil_proxy")))
        XCTAssertEqual(proxy.http, ProxyEndpoint(host: "proxy.corp.example.com", port: 8080))
        XCTAssertEqual(proxy.https, ProxyEndpoint(host: "proxy.corp.example.com", port: 8443))
        XCTAssertNil(proxy.socks, "SOCKSEnable : 1 inside __SCOPED__ is not the global setting")
        XCTAssertEqual(proxy.exceptions, ["*.local", "169.254/16", "corp.example.com"])
        XCTAssertTrue(proxy.excludesSimpleHostnames)
        XCTAssertTrue(proxy.isAnyEnabled)
        XCTAssertEqual(proxy.summary, "HTTP proxy.corp.example.com:8080, HTTPS proxy.corp.example.com:8443")
    }

    func testPACOnly() throws {
        let proxy = try XCTUnwrap(ProxyParser.parse(try fixture("scutil_proxy_none")))
        XCTAssertNil(proxy.http)
        XCTAssertEqual(proxy.autoConfigURL, "http://wpad.corp.example.com/wpad.dat")
        XCTAssertTrue(proxy.isAnyEnabled)
        XCTAssertNil(ProxyParser.parse("garbage"))
    }

    func testVPNList() throws {
        let vpns = VPNListParser.parse(try fixture("scutil_nc"))
        XCTAssertEqual(vpns.map(\.name), ["Home WireGuard", "Tailscale", "Office IPSec"])
        XCTAssertEqual(vpns.map(\.isConnected), [true, false, false])
        XCTAssertEqual(vpns.map(\.enabled), [true, true, false])
        XCTAssertEqual(vpns[0].type, "VPN:com.wireguard.macos")
    }

    func testTailscale() throws {
        let status = try XCTUnwrap(TailscaleParser.parse(try fixture("tailscale_status")))
        XCTAssertTrue(status.isRunning)
        XCTAssertEqual(status.selfName, "studio")
        XCTAssertEqual(status.selfAddresses.first, "100.101.102.103")
        XCTAssertEqual(status.tailnet, "me@example.com")
        XCTAssertEqual(status.peersTotal, 3)
        XCTAssertEqual(status.peersOnline, 2)
        XCTAssertEqual(status.exitNode, "nas")
        XCTAssertEqual(status.health.count, 1)
        XCTAssertNil(TailscaleParser.parse("{}"))
    }

    func testPreferredWiFi() throws {
        XCTAssertEqual(PreferredWiFiParser.parse(try fixture("preferred_wifi")), ["Home 5G", "Office Guest", "Cafe"])
        XCTAssertNil(PreferredWiFiParser.parse("en5 is not a Wi-Fi interface.\n** Error: Error obtaining wireless information."))
        XCTAssertTrue(NetInterfaceName.isValid("en0"))
        XCTAssertFalse(NetInterfaceName.isValid("-en0"))
    }

    func testExtrasReaderAndFindings() async throws {
        let runner = ScriptedExtrasRunner([
            "--proxy": try fixture("scutil_proxy"), "--nc": try fixture("scutil_nc"),
            "status": try fixture("tailscale_status"), "-listpreferredwirelessnetworks": try fixture("preferred_wifi"),
        ])
        let reader = SystemNetworkReader(runner: runner)
        let extras = try await reader.extras(wifiInterface: "en0",
                                             tailscale: ExecutableLocator(candidates: ["/opt/homebrew/bin/tailscale"], isExecutable: { _ in true }))
        XCTAssertEqual(extras.connectedVPNs.map(\.name), ["Home WireGuard"])
        XCTAssertEqual(extras.preferredWiFi?.count, 3)
        XCTAssertEqual(extras.tailscale?.exitNode, "nas")
        XCTAssertEqual(extras.findings.count, 4)
        XCTAssertTrue(extras.findings[0].contains("HTTP_PROXY"))
        XCTAssertEqual(try JSONDecoder().decode(NetExtras.self, from: JSONEncoder().encode(extras)), extras)
        // Not a valid interface name: networksetup is never run with it.
        let other = try await reader.extras(wifiInterface: "-x", tailscale: ExecutableLocator(candidates: [], isExecutable: { _ in false }))
        XCTAssertNil(other.preferredWiFi)
        XCTAssertNil(other.tailscale)
    }
}

/// Answers by the first argument that matches a key.
private final class ScriptedExtrasRunner: CommandRunning, @unchecked Sendable {
    let outputs: [String: String]
    init(_ outputs: [String: String]) { self.outputs = outputs }
    func run(_ executable: String, _ arguments: [String]) async throws -> CommandOutput {
        guard let text = outputs[arguments.first ?? ""] else { return CommandOutput(stdout: "", stderr: "unscripted", status: 1) }
        return CommandOutput(stdout: text, stderr: "", status: 0)
    }
}
