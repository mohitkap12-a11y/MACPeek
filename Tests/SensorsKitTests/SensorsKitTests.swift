import XCTest
@testable import SensorsKit

final class SMCValueTests: XCTestCase {
    func testFourCharacterCodes() {
        XCTAssertEqual(SMCValue.code("TC0P"), 0x5443_3050)
        XCTAssertEqual(SMCValue.text(0x5443_3050), "TC0P")
        XCTAssertEqual(SMCValue.text(SMCValue.code("flt ")), "flt ")
    }

    func testDecoding() throws {
        // 1200.5 as a little-endian Float32 (Apple silicon fan speed).
        let float = Float(1200.5).bitPattern
        let little = [UInt8(float & 0xff), UInt8(float >> 8 & 0xff), UInt8(float >> 16 & 0xff), UInt8(float >> 24 & 0xff)]
        XCTAssertEqual(try XCTUnwrap(SMCValue.decode(type: "flt ", bytes: little)), 1200.5, accuracy: 0.001)
        // fpe2: 0x1F40 = 8000 / 4 = 2000 rpm.
        XCTAssertEqual(SMCValue.decode(type: "fpe2", bytes: [0x1F, 0x40]), 2000)
        // sp78: 0x3A80 = 58.5 °C.
        XCTAssertEqual(SMCValue.decode(type: "sp78", bytes: [0x3A, 0x80]), 58.5)
        XCTAssertEqual(SMCValue.decode(type: "sp78", bytes: [0xFF, 0x00]), -1)
        XCTAssertEqual(SMCValue.decode(type: "ui8 ", bytes: [2]), 2)
        XCTAssertEqual(SMCValue.decode(type: "ui16", bytes: [0x01, 0x00]), 256)
        XCTAssertNil(SMCValue.decode(type: "ch8*", bytes: [1, 2]))
        XCTAssertNil(SMCValue.decode(type: "flt ", bytes: [1, 2]), "too short")
    }
}

final class SensorClassifierTests: XCTestCase {
    func testAppleSiliconNames() {
        XCTAssertEqual(SensorClassifier.group(forHIDName: "pACC MTR Temp Sensor2"), .cpu)
        XCTAssertEqual(SensorClassifier.group(forHIDName: "eACC MTR Temp Sensor0"), .cpu)
        XCTAssertEqual(SensorClassifier.group(forHIDName: "PMU tdie3"), .cpu)
        XCTAssertEqual(SensorClassifier.group(forHIDName: "GPU MTR Temp Sensor1"), .gpu)
        XCTAssertEqual(SensorClassifier.group(forHIDName: "ANE MTR Temp Sensor1"), .neuralEngine)
        XCTAssertEqual(SensorClassifier.group(forHIDName: "SOC MTR Temp Sensor0"), .soc)
        XCTAssertEqual(SensorClassifier.group(forHIDName: "PMU tdev1"), .soc)
        XCTAssertEqual(SensorClassifier.group(forHIDName: "NAND CH0 temp"), .storage)
        XCTAssertEqual(SensorClassifier.group(forHIDName: "gas gauge battery"), .battery)
        XCTAssertEqual(SensorClassifier.group(forHIDName: "Something new"), .other)
    }

    func testIntelKeys() {
        XCTAssertEqual(SensorClassifier.group(forSMCKey: "TC0P"), .cpu)
        XCTAssertEqual(SensorClassifier.group(forSMCKey: "TG0D"), .gpu)
        XCTAssertEqual(SensorClassifier.group(forSMCKey: "TB0T"), .battery)
        XCTAssertEqual(SensorClassifier.group(forSMCKey: "TA0P"), .ambient)
        XCTAssertEqual(SensorClassifier.group(forSMCKey: "FNum"), .other)
    }

    func testPlausibility() {
        XCTAssertTrue(SensorClassifier.isPlausible(45))
        XCTAssertFalse(SensorClassifier.isPlausible(0))
        XCTAssertFalse(SensorClassifier.isPlausible(-127))
        XCTAssertFalse(SensorClassifier.isPlausible(.nan))
    }
}

final class SensorSnapshotTests: XCTestCase {
    func testHeadlineAndSummary() throws {
        let snapshot = SensorSnapshot(temperatures: [
            TemperatureSensor(name: "a", group: .cpu, celsius: 50),
            TemperatureSensor(name: "b", group: .cpu, celsius: 70),
            TemperatureSensor(name: "c", group: .gpu, celsius: 40),
        ], fans: [FanReading(index: 0, rpm: 1500, minimumRPM: 1000, maximumRPM: 2000)], systemWatts: 18)
        XCTAssertEqual(snapshot.headlineCelsius, 70)
        XCTAssertEqual(snapshot.average(.cpu), 60)
        XCTAssertEqual(snapshot.summary.map(\.group), [.cpu, .gpu])
        XCTAssertEqual(try XCTUnwrap(snapshot.fans.first?.fraction), 0.5, accuracy: 0.0001)
        XCTAssertFalse(snapshot.isEmpty)

        let socOnly = SensorSnapshot(temperatures: [TemperatureSensor(name: "s", group: .soc, celsius: 44)], fans: [])
        XCTAssertEqual(socOnly.headlineCelsius, 44)
        XCTAssertTrue(SensorSnapshot.empty.isEmpty)
    }

    func testCodable() throws {
        let snapshot = SensorSnapshot(temperatures: [TemperatureSensor(name: "TC0P", group: .cpu, celsius: 61.25)],
                                      fans: [FanReading(index: 0, rpm: 0, minimumRPM: nil, maximumRPM: nil)], systemWatts: nil,
                                      note: "n")
        let data = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(SensorSnapshot.self, from: data), snapshot)
    }
}
