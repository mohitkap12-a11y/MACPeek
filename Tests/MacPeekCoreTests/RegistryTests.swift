import XCTest
@testable import MacPeekCore

final class RegistryTests: XCTestCase {
    func testCatalogHasUniqueIDsAndNoAudioPeek() {
        let ids = UtilityCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertFalse(ids.contains("audiopeek"))
        XCTAssertEqual(ids.count, 13)
    }

    func testEveryUtilityIsFullyDescribed() {
        for u in UtilityCatalog.all {
            XCTAssertFalse(u.name.isEmpty, u.id)
            XCTAssertFalse(u.question.isEmpty, u.id)
            XCTAssertFalse(u.tagline.isEmpty, u.id)
            XCTAssertFalse(u.summary.isEmpty, u.id)
            XCTAssertFalse(u.icon.isEmpty, u.id)
            XCTAssertFalse(u.reads.isEmpty, u.id)
            XCTAssertFalse(u.permissions.isEmpty, u.id)
            XCTAssertTrue(u.name.hasSuffix("Peek"), u.id)
        }
    }

    func testShippedUtilities() {
        let available = UtilityCatalog.all.filter(\.isAvailable).map(\.id)
        XCTAssertEqual(available, ["portpeek", "displaypeek", "usbpeek", "netpeek", "sleeppeek", "filelockpeek", "processpeek", "diskpeek", "envpeek", "dnspeek", "soundpeek", "updatepeek"])
    }

    func testPortPeekIsAvailable() {
        XCTAssertTrue(UtilityCatalog.portPeek.isAvailable)
        XCTAssertEqual(UtilityCatalog.info(for: "portpeek")?.name, "PortPeek")
        XCTAssertNil(UtilityCatalog.info(for: "nope"))
    }

    // Selection uses a custom catalog so these tests do not change as utilities ship.
    private func info(_ id: String, _ availability: UtilityAvailability) -> UtilityInfo {
        UtilityInfo(id: id, name: id, question: "q", tagline: "t", summary: "s", icon: "i",
                    category: .everyday, availability: availability, reads: ["r"], permissions: ["p"])
    }

    func testAvailableUtilitiesAreEnabledByDefaultAndComingSoonNever() {
        let catalog = [info("a", .available), info("b", .available), info("c", .comingSoon)]
        let s = UtilitySelection(catalog: catalog)
        XCTAssertTrue(s.isEnabled("a"))
        XCTAssertTrue(s.isEnabled("b"))
        XCTAssertFalse(s.isEnabled("c"))
        XCTAssertFalse(s.isEnabled("unknown"))
        XCTAssertEqual(s.enabledUtilities.map(\.id), ["a", "b"])
        XCTAssertEqual(s.availableCount, 2)
    }

    func testDisableAndReEnable() {
        var s = UtilitySelection(catalog: [info("a", .available), info("b", .available)])
        XCTAssertTrue(s.setEnabled("a", false))
        XCTAssertFalse(s.isEnabled("a"))
        XCTAssertEqual(s.enabledCount, 1)
        XCTAssertEqual(s.storageValue, ["a"])
        XCTAssertTrue(s.setEnabled("a", true))
        XCTAssertTrue(s.isEnabled("a"))
        XCTAssertEqual(s.storageValue, [])
    }

    func testComingSoonCannotBeToggled() {
        var s = UtilitySelection(catalog: [info("c", .comingSoon)])
        XCTAssertFalse(s.setEnabled("c", true))
        XCTAssertFalse(s.setEnabled("c", false))
        XCTAssertFalse(s.isEnabled("c"))
        XCTAssertTrue(s.disabled.isEmpty)
        XCTAssertFalse(s.setEnabled("unknown", true))
    }

    func testPersistedDisabledSetLeavesNewlyShippedUtilitiesEnabled() {
        // The user disabled "a" in an old version. "b" shipped later: it must show up enabled.
        let s = UtilitySelection(storedDisabled: ["a"], catalog: [info("a", .available), info("b", .available)])
        XCTAssertFalse(s.isEnabled("a"))
        XCTAssertTrue(s.isEnabled("b"))
        XCTAssertEqual(UtilitySelection(storedDisabled: nil, catalog: [info("a", .available)]).enabledCount, 1)
    }

    func testDisabledSetForUnknownUtilitiesIsIgnored() {
        let s = UtilitySelection(storedDisabled: ["removed-utility"], catalog: [info("a", .available)])
        XCTAssertTrue(s.isEnabled("a"))
    }
}
