import XCTest
@testable import RemoteAgent

final class HardwareBindingTests: XCTestCase {
    func testKeyMadeOnThisMacIsKept() {
        XCTAssertEqual(HardwareBinding.decide(stored: "A", current: "A"), .keep)
    }

    func testKeyCopiedFromAnotherMacIsReplaced() {
        // Migration Assistant or a Time Machine restore brought the old Mac's key.
        XCTAssertEqual(HardwareBinding.decide(stored: "OLD-MAC", current: "NEW-MAC"), .replace("NEW-MAC"))
    }

    func testKeyFromBeforeTheBindingIsKeptAndBound() {
        // Existing installs keep their key (and every console that knows it).
        XCTAssertEqual(HardwareBinding.decide(stored: nil, current: "A"), .bind("A"))
        XCTAssertEqual(HardwareBinding.decide(stored: "", current: "A"), .bind("A"))
    }

    func testUnknownHardwareNeverReplacesTheKey() {
        XCTAssertEqual(HardwareBinding.decide(stored: "A", current: nil), .keep)
        XCTAssertEqual(HardwareBinding.decide(stored: nil, current: nil), .keep)
        XCTAssertEqual(HardwareBinding.decide(stored: "A", current: ""), .keep)
    }
}
