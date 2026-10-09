import XCTest
@testable import SoundPeekKit

/// In-memory provider: a mutable device list stands in for Core Audio.
final class FakeAudioProvider: AudioDeviceProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var devices: [AudioDevice]
    private var defaultInput: UInt32?
    private var defaultOutput: UInt32?
    var failSnapshot: Error?
    private(set) var setDefaultCalls: [(UInt32, AudioDirection)] = []
    private(set) var muteCalls: [(Bool, UInt32)] = []

    init(devices: [AudioDevice], defaultInput: UInt32? = nil, defaultOutput: UInt32? = nil) {
        self.devices = devices
        self.defaultInput = defaultInput
        self.defaultOutput = defaultOutput
    }

    func remove(_ id: UInt32) { lock.lock(); devices.removeAll { $0.id == id }; lock.unlock() }

    func snapshot() async throws -> AudioSnapshot {
        if let failSnapshot { throw failSnapshot }
        lock.lock(); defer { lock.unlock() }
        return AudioSnapshot(devices: devices, defaultInputID: defaultInput, defaultOutputID: defaultOutput)
    }

    func setDefaultDevice(_ id: UInt32, direction: AudioDirection) async throws {
        lock.lock(); defer { lock.unlock() }
        setDefaultCalls.append((id, direction))
        if direction == .input { defaultInput = id } else { defaultOutput = id }
    }

    func setMuted(_ muted: Bool, deviceID: UInt32, direction: AudioDirection) async throws {
        lock.lock(); defer { lock.unlock() }
        muteCalls.append((muted, deviceID))
    }
}

private let speakers = AudioDevice(id: 1, name: "MacBook Pro Speakers", transport: .builtIn, inputChannels: 0, outputChannels: 2,
                                   sampleRate: 48_000,
                                   outputControls: AudioControls(volume: 0.45, isMuted: false, canSetMute: true))
private let microphone = AudioDevice(id: 2, name: "MacBook Pro Microphone", transport: .builtIn, inputChannels: 1, outputChannels: 0,
                                     sampleRate: 48_000)
private let airpods = AudioDevice(id: 3, name: "AirPods Pro", transport: .bluetooth, inputChannels: 1, outputChannels: 2,
                                  sampleRate: 44_100)
private let hdmi = AudioDevice(id: 4, name: "Display Audio", transport: .hdmi, inputChannels: 0, outputChannels: 2,
                               outputControls: AudioControls(volume: nil, isMuted: nil, canSetMute: true))

final class AudioModelTests: XCTestCase {
    func testTransportMapsFourCharacterCodes() {
        XCTAssertEqual(AudioTransport.from(code: AudioTransport.fourCC("bltn")), .builtIn)
        XCTAssertEqual(AudioTransport.from(code: AudioTransport.fourCC("usb ")), .usb)
        XCTAssertEqual(AudioTransport.from(code: AudioTransport.fourCC("blue")), .bluetooth)
        XCTAssertEqual(AudioTransport.from(code: AudioTransport.fourCC("hdmi")), .hdmi)
        XCTAssertEqual(AudioTransport.from(code: AudioTransport.fourCC("grup")), .aggregate)
        XCTAssertEqual(AudioTransport.from(code: nil), .unknown)
        XCTAssertEqual(AudioTransport.from(code: 0), .unknown)
        XCTAssertEqual(AudioTransport.from(code: 42), .other(42))
        XCTAssertEqual(AudioTransport.other(42).label, "Other")
    }

    func testFormatLabelsOnlyUseReportedParts() {
        XCTAssertEqual(speakers.formatLabel(.output), "48 kHz · Stereo")
        XCTAssertEqual(microphone.formatLabel(.input), "48 kHz · 1 channel")
        XCTAssertEqual(airpods.sampleRateLabel, "44.1 kHz")
        XCTAssertEqual(hdmi.formatLabel(.output), "Stereo")
        let bare = AudioDevice(id: 9, name: "Mystery")
        XCTAssertNil(bare.formatLabel(.output))
        XCTAssertFalse(bare.hasInput)
        XCTAssertFalse(bare.hasOutput)
    }

    func testControlsNeverClaimWritableMuteWithoutAMuteValue() {
        XCTAssertFalse(hdmi.outputControls.canSetMute)
        XCTAssertNil(hdmi.outputControls.volumeLabel)
        XCTAssertEqual(speakers.outputControls.volumeLabel, "45%")
        XCTAssertEqual(AudioControls(volume: 7).volume, 1)
    }

    func testEmptyNameBecomesUnnamed() {
        XCTAssertEqual(AudioDevice(id: 5, name: "").name, "Unnamed device")
    }

    func testDevicesForDirectionPutsDefaultThenBuiltInFirst() {
        let snapshot = AudioSnapshot(devices: [hdmi, airpods, speakers, microphone], defaultInputID: 3, defaultOutputID: 3)
        XCTAssertEqual(snapshot.devices(for: .output).map(\.id), [3, 1, 4])
        XCTAssertEqual(snapshot.devices(for: .input).map(\.id), [3, 2])
        XCTAssertEqual(snapshot.defaultDevice(.output)?.name, "AirPods Pro")
    }

    func testDefaultThatIsNotInTheListIsNil() {
        let snapshot = AudioSnapshot(devices: [speakers], defaultInputID: 99, defaultOutputID: nil)
        XCTAssertNil(snapshot.defaultDevice(.input))
        XCTAssertNil(snapshot.defaultDevice(.output))
    }

    func testDuplicateNamesAreToldApart() {
        let a = AudioDevice(id: 10, name: "USB Audio", transport: .usb, outputChannels: 2)
        let b = AudioDevice(id: 11, name: "USB Audio", transport: .usb, outputChannels: 2)
        let c = AudioDevice(id: 12, name: "Headset", transport: .usb, outputChannels: 2)
        let d = AudioDevice(id: 13, name: "Headset", transport: .bluetooth, outputChannels: 2)
        let names = AudioSnapshot(devices: [a, b, c, d], defaultInputID: nil, defaultOutputID: nil).displayNames()
        XCTAssertEqual(names[10], "USB Audio (1)")
        XCTAssertEqual(names[11], "USB Audio (2)")
        XCTAssertEqual(names[12], "Headset (USB)")
        XCTAssertEqual(names[13], "Headset (Bluetooth)")
        XCTAssertEqual(Set(names.values).count, 4)
    }

    func testDiagnosticReportHasNoIdentifiers() {
        let report = AudioSnapshot(devices: [speakers, microphone], defaultInputID: 2, defaultOutputID: 1)
            .diagnosticReport(macOSVersion: "15.1")
        XCTAssertTrue(report.contains("macOS: 15.1"))
        XCTAssertTrue(report.contains("MacBook Pro Speakers, Built-in, 48 kHz · Stereo, volume 45%, not muted, default"))
    }
}

final class SoundPeekServiceTests: XCTestCase {
    private func service(_ provider: FakeAudioProvider) -> SoundPeekService { SoundPeekService(provider: provider) }

    func testSettingDefaultReportsThePreviousDeviceForUndo() async throws {
        let provider = FakeAudioProvider(devices: [speakers, airpods], defaultOutput: 1)
        let (snapshot, change) = try await service(provider).setDefault(3, direction: .output)
        XCTAssertEqual(snapshot.defaultOutputID, 3)
        XCTAssertEqual(change, DefaultDeviceChange(direction: .output, previousID: 1, newID: 3))
        let restored = try await service(provider).restore(try XCTUnwrap(change))
        XCTAssertEqual(restored.defaultOutputID, 1)
    }

    func testSettingTheCurrentDefaultChangesNothing() async throws {
        let provider = FakeAudioProvider(devices: [speakers], defaultOutput: 1)
        let (_, change) = try await service(provider).setDefault(1, direction: .output)
        XCTAssertNil(change)
        XCTAssertTrue(provider.setDefaultCalls.isEmpty)
    }

    func testRemovedDeviceIsRefusedAndNothingIsSent() async {
        let provider = FakeAudioProvider(devices: [speakers, airpods], defaultOutput: 1)
        provider.remove(3)
        do {
            _ = try await service(provider).setDefault(3, direction: .output)
            XCTFail("expected deviceUnavailable")
        } catch {
            XCTAssertEqual(error as? SoundPeekError, .deviceUnavailable)
        }
        XCTAssertTrue(provider.setDefaultCalls.isEmpty)
    }

    func testDeviceWithoutThatDirectionIsRefused() async {
        let provider = FakeAudioProvider(devices: [speakers, microphone])
        do {
            _ = try await service(provider).setDefault(1, direction: .input)
            XCTFail("expected notSupported")
        } catch {
            guard case SoundPeekError.notSupported = error else { return XCTFail("wrong error \(error)") }
        }
        XCTAssertTrue(provider.setDefaultCalls.isEmpty)
    }

    func testRestoreFailsWhenThePreviousDeviceIsGone() async {
        let provider = FakeAudioProvider(devices: [speakers, airpods], defaultOutput: 1)
        let change = DefaultDeviceChange(direction: .output, previousID: 1, newID: 3)
        provider.remove(1)
        do {
            _ = try await service(provider).restore(change)
            XCTFail("expected deviceUnavailable")
        } catch {
            XCTAssertEqual(error as? SoundPeekError, .deviceUnavailable)
        }
    }

    func testMuteOnlyWhenTheDeviceAllowsIt() async throws {
        let provider = FakeAudioProvider(devices: [speakers, hdmi], defaultOutput: 1)
        _ = try await service(provider).setMuted(true, deviceID: 1, direction: .output)
        XCTAssertEqual(provider.muteCalls.count, 1)
        do {
            _ = try await service(provider).setMuted(true, deviceID: 4, direction: .output)
            XCTFail("expected notSupported")
        } catch {
            guard case SoundPeekError.notSupported = error else { return XCTFail("wrong error \(error)") }
        }
        XCTAssertEqual(provider.muteCalls.count, 1)
    }

    func testProviderErrorsPropagate() async {
        let provider = FakeAudioProvider(devices: [])
        provider.failSnapshot = SoundPeekError.operationFailed("boom")
        do {
            _ = try await service(provider).snapshot()
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? SoundPeekError, .operationFailed("boom"))
        }
    }
}
