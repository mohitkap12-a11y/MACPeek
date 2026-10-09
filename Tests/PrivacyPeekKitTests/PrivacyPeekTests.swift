import XCTest
@testable import PrivacyPeekKit
import MacPeekCore

final class PrivacyCatalogTests: XCTestCase {
    func testEveryRequestedCategoryIsPresentOnTheLatestVersion() {
        let names = PrivacyCatalog.categories(forMajorVersion: 15).map(\.name)
        for expected in ["Camera", "Microphone", "Screen & System Audio Recording", "Accessibility", "Full Disk Access",
                         "Files & Folders", "Location Services", "Contacts", "Calendars", "Photos", "Bluetooth",
                         "Local Network", "Input Monitoring"] {
            XCTAssertTrue(names.contains(expected), expected)
        }
    }

    func testOlderVersionsUseTheOlderNameAndOmitLocalNetwork() {
        let categories = PrivacyCatalog.categories(forMajorVersion: 13)
        XCTAssertTrue(categories.contains { $0.name == "Screen Recording" })
        XCTAssertFalse(categories.contains { $0.name.contains("System Audio") })
        XCTAssertFalse(categories.contains { $0.id == "localNetwork" })
        XCTAssertNil(categories.first { $0.id == "screen" }?.note)
    }

    func testIDsAreUniqueAndEveryEntryIsFullyDescribed() {
        for major in [13, 14, 15, 26] {
            let categories = PrivacyCatalog.categories(forMajorVersion: major)
            XCTAssertEqual(Set(categories.map(\.id)).count, categories.count)
            for category in categories {
                XCTAssertFalse(category.name.isEmpty)
                XCTAssertFalse(category.summary.isEmpty)
                XCTAssertFalse(category.whatItAllows.isEmpty)
                XCTAssertFalse(category.symbol.isEmpty)
            }
        }
    }

    func testEveryRouteIsAValidSettingsURLWithAGenericFallback() {
        for category in PrivacyCatalog.categories(forMajorVersion: 15) {
            let urls = category.pane.candidateURLs
            XCTAssertEqual(urls.count, category.pane.urlStrings.count, category.id)
            XCTAssertTrue(urls.allSatisfy { $0.scheme == SystemSettingsPane.scheme }, category.id)
            XCTAssertEqual(category.pane.urlStrings.last, SystemSettingsPane.rootURLString, category.id)
            XCTAssertTrue(category.pane.urlStrings.contains(SystemSettingsPane.privacyAndSecurity.urlStrings[0]), category.id)
            XCTAssertTrue(category.pane.urlStrings[0].contains("Privacy_"), category.id)
        }
    }

    func testCopyDoesNotMakeSecurityClaims() {
        let text = PrivacyCatalog.categories(forMajorVersion: 15).map(\.copyText).joined(separator: " ").lowercased()
        for word in ["malware", "malicious", "virus"] { XCTAssertFalse(text.contains(word), word) }
    }

    func testDisclaimerStatesTheLimits() {
        let text = PrivacyCatalog.disclaimer.lowercased()
        XCTAssertTrue(text.contains("does not read which apps"))
        XCTAssertTrue(text.contains("cannot grant, revoke or reset"))
        XCTAssertTrue(PrivacyCatalog.notAVerdict.contains("does not mean an app is unsafe"))
    }
}

final class SystemSettingsPaneTests: XCTestCase {
    func testFixedPanesAreWellFormed() {
        for pane in [SystemSettingsPane.sound, .loginItems, .softwareUpdate, .privacyAndSecurity] {
            XCTAssertFalse(pane.candidateURLs.isEmpty, pane.id)
            XCTAssertEqual(pane.candidateURLs.count, pane.urlStrings.count, pane.id)
            XCTAssertEqual(pane.urlStrings.last, SystemSettingsPane.rootURLString, pane.id)
        }
        XCTAssertTrue(SystemSettingsPane.sound.urlStrings[0].hasSuffix("com.apple.Sound-Settings.extension"))
        XCTAssertTrue(SystemSettingsPane.loginItems.urlStrings[0].hasSuffix("com.apple.LoginItems-Settings.extension"))
    }
}
