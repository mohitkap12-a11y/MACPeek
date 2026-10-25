import XCTest
import SoundPeekKit

/// Encodes to JSON and back; the value must survive unchanged so a MacPeek Remote console can read it.
private func assertRoundTrips<T: Codable & Equatable>(_ value: T, file: StaticString = #filePath, line: UInt = #line) throws {
    let data = try JSONEncoder().encode(value)
    XCTAssertEqual(try JSONDecoder().decode(T.self, from: data), value, file: file, line: line)
}

final class CodableTests: XCTestCase {
    func testAudioSnapshotRoundTrips() throws {
        let speakers = AudioDevice(id: 73, name: "Studio Display Speakers", transport: .usb, outputChannels: 2, sampleRate: 48_000,
                                   outputControls: AudioControls(volume: 0.4, isMuted: false, canSetMute: true, canSetVolume: true))
        let custom = AudioDevice(id: 91, name: "Interface", transport: .other(0x7465_7374), inputChannels: 8)
        try assertRoundTrips(AudioSnapshot(devices: [speakers, custom], defaultInputID: 91, defaultOutputID: 73,
                                           updatedAt: Date(timeIntervalSince1970: 1_761_390_724)))
        try assertRoundTrips(AudioDirection.allCases)
    }
}
