import XCTest
@testable import StartupPeekKit

private func plistData(_ dictionary: [String: Any]) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
}

/// Writes plists into a throwaway folder; nothing outside it is touched.
private final class Folder {
    let url: URL
    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("startuppeek-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }
    func write(_ name: String, _ data: Data) throws { try data.write(to: url.appendingPathComponent(name)) }
    func location(_ category: StartupCategory = .userLaunchAgent, scope: StartupScope = .currentUser) -> LaunchdLocation {
        LaunchdLocation(path: url.path, category: category, scope: scope, source: .userLaunchAgents)
    }
}

private struct FakeSignatures: CodeSignatureReading {
    var answers: [String: SignatureInfo] = [:]
    func signature(atPath path: String) -> SignatureInfo { answers[path] ?? .unavailable }
}

final class LaunchdPlistParserTests: XCTestCase {
    func testParsesTheFieldsStartupPeekUses() throws {
        let data = try plistData([
            "Label": "com.example.agent",
            "ProgramArguments": ["/Applications/Example.app/Contents/MacOS/helper", "--flag"],
            "RunAtLoad": true,
            "AssociatedBundleIdentifiers": ["com.example.App"],
        ])
        let description = try LaunchdPlistParser.parse(data)
        XCTAssertEqual(description.label, "com.example.agent")
        XCTAssertEqual(description.executablePath, "/Applications/Example.app/Contents/MacOS/helper")
        XCTAssertEqual(description.status, .startsAutomatically)
        XCTAssertEqual(description.associatedBundleIdentifiers, ["com.example.App"])
    }

    func testProgramWinsOverProgramArguments() throws {
        let description = try LaunchdPlistParser.parse(try plistData(["Program": "/usr/bin/a", "ProgramArguments": ["/usr/bin/b"]]))
        XCTAssertEqual(description.executablePath, "/usr/bin/a")
    }

    func testStatusRules() throws {
        func status(_ dictionary: [String: Any]) throws -> StartupStatus { try LaunchdPlistParser.parse(try plistData(dictionary)).status }
        XCTAssertEqual(try status(["Disabled": true, "RunAtLoad": true]), .disabledInFile)
        XCTAssertEqual(try status(["KeepAlive": true]), .startsAutomatically)
        XCTAssertEqual(try status(["KeepAlive": ["SuccessfulExit": false]]), .startsAutomatically)
        XCTAssertEqual(try status(["KeepAlive": false]), .unknown)
        XCTAssertEqual(try status(["StartInterval": 300]), .startsOnDemand)
        XCTAssertEqual(try status(["Label": "x"]), .unknown)
    }

    func testWrongTypesAreIgnoredNotTrusted() throws {
        let description = try LaunchdPlistParser.parse(try plistData([
            "Label": 42, "ProgramArguments": "not-an-array", "RunAtLoad": "yes",
        ]))
        XCTAssertNil(description.label)
        XCTAssertNil(description.executablePath)
        XCTAssertFalse(description.runAtLoad)
    }

    func testMalformedInputThrows() {
        XCTAssertThrowsError(try LaunchdPlistParser.parse(Data("not a plist".utf8)))
        XCTAssertThrowsError(try LaunchdPlistParser.parse(Data()))
        // A valid plist whose root is an array, not a dictionary.
        let array = try? PropertyListSerialization.data(fromPropertyList: ["a"], format: .xml, options: 0)
        XCTAssertThrowsError(try LaunchdPlistParser.parse(array ?? Data()))
    }

    func testOversizedInputIsRefused() {
        XCTAssertThrowsError(try LaunchdPlistParser.parse(Data(count: LaunchdPlistParser.maxBytes + 1)))
    }
}

final class AttributionTests: XCTestCase {
    func testAppBundleAndName() {
        let path = "/Applications/Example App.app/Contents/Library/LoginItems/Helper.app/Contents/MacOS/Helper"
        XCTAssertEqual(Attribution.enclosingAppBundle(of: path), "/Applications/Example App.app")
        XCTAssertEqual(Attribution.appName(from: path), "Example App")
        XCTAssertNil(Attribution.enclosingAppBundle(of: "/usr/local/bin/tool"))
        XCTAssertNil(Attribution.enclosingAppBundle(of: "/opt/.app/x"))
        XCTAssertEqual(Attribution.appName(fromBundleIdentifier: "com.example.Helper"), "Helper")
        XCTAssertNil(Attribution.appName(fromBundleIdentifier: ""))
    }

    func testCommonLocations() {
        XCTAssertTrue(Attribution.isInCommonLocation("/Applications/A.app/x", home: "/Users/me"))
        XCTAssertTrue(Attribution.isInCommonLocation("/Users/me/Applications/A.app/x", home: "/Users/me"))
        XCTAssertTrue(Attribution.isInCommonLocation("/Users/me/Library/Application Support/x/y", home: "/Users/me"))
        XCTAssertFalse(Attribution.isInCommonLocation("/tmp/x", home: "/Users/me"))
        XCTAssertFalse(Attribution.isInCommonLocation("/Users/me/Downloads/x", home: "/Users/me"))
    }

    func testObservationsAreNeutral() {
        let notes = Attribution.observations(executablePath: "/tmp/x", signature: .unsigned, executableExists: true, home: "/Users/me")
        XCTAssertEqual(notes, ["Path is outside common application locations", "Attribution could not be verified"])
        let missing = Attribution.observations(executablePath: "/Applications/Gone", signature: .unavailable, executableExists: false, home: "/Users/me")
        XCTAssertEqual(missing, ["The executable was not found at the listed path"])
        let signed = Attribution.observations(executablePath: "/Applications/A", signature: .signed(teamID: "ABCDE12345", identifier: nil),
                                              executableExists: true, home: "/Users/me")
        XCTAssertTrue(signed.isEmpty)
        for note in notes + missing {
            for word in ["malware", "suspicious", "unsafe", "virus"] { XCTAssertFalse(note.lowercased().contains(word)) }
        }
    }
}

final class StartupInventoryTests: XCTestCase {
    func testReadsFolderAndNeverModifiesIt() async throws {
        let folder = try Folder()
        try folder.write("com.example.agent.plist", try plistData([
            "Label": "com.example.agent", "ProgramArguments": ["/Applications/Example.app/Contents/MacOS/helper"], "RunAtLoad": true,
        ]))
        try folder.write("notes.txt", Data("ignored".utf8))
        let before = try FileManager.default.contentsOfDirectory(atPath: folder.url.path).sorted()

        let result = await LaunchdPlistProvider(locations: [folder.location()]).items()

        XCTAssertEqual(result.items.count, 1)
        let item = try XCTUnwrap(result.items.first)
        XCTAssertEqual(item.name, "Example")
        XCTAssertEqual(item.attributionLine, "Likely associated with Example")
        XCTAssertEqual(item.category, .userLaunchAgent)
        XCTAssertEqual(item.status, .startsAutomatically)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.url.path).sorted(), before)
    }

    func testMalformedPlistStillAppearsAsUnknown() async throws {
        let folder = try Folder()
        try folder.write("broken.plist", Data("<<<garbage".utf8))
        let result = await LaunchdPlistProvider(locations: [folder.location(.launchDaemon, scope: .system)]).items()
        let item = try XCTUnwrap(result.items.first)
        XCTAssertEqual(item.name, "broken")
        XCTAssertEqual(item.status, .unknown)
        XCTAssertEqual(item.category, .launchDaemon)
        XCTAssertEqual(item.observations, ["The property list is malformed or unreadable"])
    }

    func testOversizedPlistIsRejectedAsMalformed() async throws {
        let folder = try Folder()
        try folder.write("huge.plist", Data(count: LaunchdPlistParser.maxBytes + 4096))
        let result = await LaunchdPlistProvider(locations: [folder.location()]).items()
        let item = try XCTUnwrap(result.items.first)
        XCTAssertEqual(item.status, .unknown)
        XCTAssertEqual(item.observations, ["The property list is malformed or unreadable"])
    }

    func testMissingFolderIsNotAnError() async {
        let missing = LaunchdLocation(path: "/definitely/not/here-\(UUID().uuidString)", category: .launchDaemon,
                                      scope: .system, source: .launchDaemons)
        let result = await LaunchdPlistProvider(locations: [missing]).items()
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertTrue(result.limitations.isEmpty)
    }

    func testFolderCapIsReportedAsALimitation() async throws {
        let folder = try Folder()
        for index in 0..<3 { try folder.write("a\(index).plist", try plistData(["Label": "a\(index)"])) }
        let result = await LaunchdPlistProvider(locations: [folder.location()], maxFilesPerFolder: 2).items()
        XCTAssertEqual(result.items.count, 2)
        XCTAssertEqual(result.limitations.count, 1)
    }

    func testSharedLabelsAreFlaggedAndBothStayListed() async throws {
        let folder = try Folder()
        try folder.write("one.plist", try plistData(["Label": "com.dup", "ProgramArguments": ["/usr/bin/true"]]))
        try folder.write("two.plist", try plistData(["Label": "com.dup", "ProgramArguments": ["/usr/bin/false"]]))
        let service = StartupInventoryService(providers: [LaunchdPlistProvider(locations: [folder.location()])])
        let inventory = try await service.inventory()
        XCTAssertEqual(inventory.items.count, 2)
        XCTAssertEqual(Set(inventory.items.map(\.id)).count, 2)
        XCTAssertTrue(inventory.items.allSatisfy { $0.observations.contains("Another item uses the same label") })
    }

    func testSignatureAttributionAndMissingSignature() async throws {
        let folder = try Folder()
        // /bin/sh exists on macOS and Linux, so the "exists" branch is exercised.
        try folder.write("a.plist", try plistData(["Label": "com.a", "ProgramArguments": ["/bin/sh"]]))
        try folder.write("b.plist", try plistData(["Label": "com.b", "ProgramArguments": ["/no/such/exe"]]))
        let signatures = FakeSignatures(answers: ["/bin/sh": .signed(teamID: "ABCDE12345", identifier: "sh")])
        let service = StartupInventoryService(providers: [LaunchdPlistProvider(locations: [folder.location()])], signatures: signatures)
        let inventory = try await service.inventory()
        let a = try XCTUnwrap(inventory.items.first { $0.label == "com.a" })
        let b = try XCTUnwrap(inventory.items.first { $0.label == "com.b" })
        XCTAssertEqual(a.signature, .signed(teamID: "ABCDE12345", identifier: "sh"))
        XCTAssertTrue(a.signature.summary.contains("not validated"))
        XCTAssertEqual(b.signature, .unavailable)
        XCTAssertTrue(b.observations.contains("The executable was not found at the listed path"))
    }

    func testInventoryAlwaysStatesItsLimitsAndSortsByCategory() async throws {
        let agent = StartupItem(id: "a", name: "Zeta", category: .userLaunchAgent, scope: .currentUser, status: .unknown, source: .userLaunchAgents)
        let login = StartupItem(id: "l", name: "Alpha", category: .loginItem, scope: .currentUser, status: .enabled, source: .serviceManagement)
        struct Fixed: StartupItemProviding {
            let result: ProviderResult
            func items() async -> ProviderResult { result }
        }
        let inventory = try await StartupInventoryService(providers: [Fixed(result: ProviderResult(items: [agent, login]))]).inventory()
        XCTAssertEqual(inventory.items.map(\.id), ["l", "a"])
        XCTAssertTrue(inventory.limitations.contains(StartupInventoryService.completenessLimitation))
        XCTAssertEqual(inventory.items(in: .loginItem).count, 1)
    }

    func testOwnLoginItemMapping() async {
        struct Reader: OwnLoginItemReading {
            let value: OwnLoginItemState?
            func state() -> OwnLoginItemState? { value }
        }
        func status(_ state: OwnLoginItemState?) async -> StartupStatus? {
            await OwnLoginItemProvider(reader: Reader(value: state)).items().items.first?.status
        }
        let enabled = await status(.enabled)
        let approval = await status(.requiresApproval)
        let notFound = await status(.notFound)
        let none = await status(nil)
        XCTAssertEqual(enabled, .enabled)
        XCTAssertEqual(approval, .requiresApproval)
        XCTAssertEqual(notFound, .notRegistered)
        XCTAssertNil(none)
    }

    func testSearchMatchesNameLabelPathAndTeam() {
        let item = StartupItem(id: "1", name: "Example", label: "com.example.agent", category: .userLaunchAgent, scope: .currentUser,
                               status: .unknown, source: .userLaunchAgents, executablePath: "/Applications/Example.app/x",
                               signature: .signed(teamID: "ABCDE12345", identifier: nil))
        let other = StartupItem(id: "2", name: "Other", category: .launchDaemon, scope: .system, status: .unknown, source: .launchDaemons)
        let items = [item, other]
        XCTAssertEqual(StartupSearch.filter(items, query: "").count, 2)
        XCTAssertEqual(StartupSearch.filter(items, query: "EXAMPLE").map(\.id), ["1"])
        XCTAssertEqual(StartupSearch.filter(items, query: "abcde12345").map(\.id), ["1"])
        XCTAssertEqual(StartupSearch.filter(items, query: "daemon").map(\.id), ["2"])
        XCTAssertTrue(StartupSearch.filter(items, query: "nomatch").isEmpty)
    }
}
