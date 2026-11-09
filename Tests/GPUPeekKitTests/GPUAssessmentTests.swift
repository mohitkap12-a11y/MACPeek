import XCTest
@testable import GPUPeekKit
import MacPeekCore

final class GPUAssessmentTests: XCTestCase {
    private func gpu(utilization: Double?, inUse: UInt64? = 1_288_490_188, vramUsed: UInt64? = nil, vramTotal: UInt64? = nil) -> GPUInfo {
        GPUInfo(name: "Apple M2 Pro", registryClass: "AGXAcceleratorG14X", coreCount: 19, deviceUtilization: utilization,
                rendererUtilization: nil, tilerUtilization: nil, memoryInUseBytes: inUse, memoryAllocatedBytes: nil,
                vramTotalBytes: vramTotal, vramUsedBytes: vramUsed, unifiedMemory: vramTotal == nil)
    }

    private let facts = GPUDeviceFacts(name: "Apple M2 Pro", hasUnifiedMemory: true, recommendedMaxWorkingSetBytes: 12_884_901_888,
                                       maxBufferBytes: 9_663_676_416, gpuFamily: "Apple 8", supportsMetal3: true,
                                       isLowPower: false, isRemovable: false)

    func testLauncherRing() throws {
        let reading = try XCTUnwrap(GPUAssessment.gaugeReading(gpu(utilization: 37)))
        XCTAssertEqual(reading.value, "37%")
        XCTAssertEqual(reading.fraction, 0.37, accuracy: 0.0001)
        XCTAssertEqual(reading.caption, "1.2 GB in use")
        XCTAssertFalse(reading.isAlert)
        XCTAssertTrue(try XCTUnwrap(GPUAssessment.gaugeReading(gpu(utilization: 95))).isAlert)
        XCTAssertNil(GPUAssessment.gaugeReading(gpu(utilization: nil)), "no utilization is not shown as 0 %")
    }

    func testCaptionFallsBackToVRAMThenName() {
        XCTAssertEqual(GPUAssessment.caption(gpu(utilization: 4, inUse: nil, vramUsed: 1_073_741_824, vramTotal: 4_294_967_296)), "1.0 GB VRAM")
        XCTAssertEqual(GPUAssessment.caption(gpu(utilization: 4, inUse: nil)), "Apple M2 Pro")
    }

    func testMemoryFraction() {
        XCTAssertEqual(GPUAssessment.memoryFraction(gpu(utilization: 1), facts: facts) ?? -1, 0.1, accuracy: 0.001)
        XCTAssertEqual(GPUAssessment.memoryFraction(gpu(utilization: 1, inUse: nil, vramUsed: 1, vramTotal: 4), facts: nil), 0.25)
        XCTAssertNil(GPUAssessment.memoryFraction(gpu(utilization: 1), facts: nil))
    }

    func testHeadline() {
        let working = PowerReading(cpuWatts: 1, gpuWatts: 1, neuralEngineWatts: 0.8, intervalSeconds: 1)
        XCTAssertEqual(GPUAssessment.headline(gpu(utilization: 2), power: nil), "The GPU is idle.")
        XCTAssertEqual(GPUAssessment.headline(gpu(utilization: 60), power: working), "The GPU is busy. The Neural Engine is working.")
        XCTAssertEqual(GPUAssessment.headline(gpu(utilization: 97), power: nil), "The GPU is fully busy.")
        XCTAssertEqual(GPUAssessment.headline(nil, power: nil), "macOS lists no GPU")
    }

    func testAppleFamily() {
        XCTAssertEqual(GPUAssessment.appleFamily { $0 <= 8 }, "Apple 8")
        XCTAssertNil(GPUAssessment.appleFamily { _ in false })
    }

    func testSnapshotCarriesDeviceFactsAndGPUsOnlyReadSkipsPower() async throws {
        struct Facts: GPUDeviceFactsReading { let list: [GPUDeviceFacts]; func facts() -> [GPUDeviceFacts] { list } }
        final class CountingPower: PowerSampling, @unchecked Sendable {
            var unavailableReason: String? { nil }
            var samples = 0
            func sample() -> PowerReading? { samples += 1; return nil }
        }
        let power = CountingPower()
        let reader = SystemGPUReader(runner: ScriptedRunner(["-r": ok(try fixture("ioreg_gpu_apple"))]), power: power,
                                     hasNeuralEngine: true, deviceFacts: Facts(list: [facts]))
        let gpus = try await reader.gpus()
        XCTAssertEqual(gpus.first?.deviceUtilization, 37)
        XCTAssertEqual(power.samples, 0, "the launcher read never touches the power counters")
        let snapshot = try await reader.snapshot(previousClients: nil, interval: 0).0
        XCTAssertEqual(snapshot.device, facts)
        XCTAssertEqual(power.samples, 1)
        XCTAssertEqual(try JSONDecoder().decode(GPUSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
    }
}
