import XCTest
@testable import GPUPeekKit
import MacPeekCore

final class GPUParserTests: XCTestCase {
    func testAppleSiliconGPU() throws {
        let result = try XCTUnwrap(IORegGPUParser.parse(try fixture("ioreg_gpu_apple")))
        let gpu = try XCTUnwrap(result.gpus.first)
        XCTAssertEqual(gpu.name, "Apple M2 Pro")
        XCTAssertEqual(gpu.registryClass, "AGXAcceleratorG14X")
        XCTAssertEqual(gpu.coreCount, 19)
        XCTAssertEqual(gpu.deviceUtilization, 37)
        XCTAssertEqual(gpu.rendererUtilization, 35)
        XCTAssertEqual(gpu.tilerUtilization, 12)
        XCTAssertEqual(gpu.memoryInUseBytes, 1_288_490_188)
        XCTAssertEqual(gpu.memoryAllocatedBytes, 2_147_483_648)
        XCTAssertTrue(gpu.unifiedMemory)
        XCTAssertNil(gpu.vramTotalBytes)
        XCTAssertEqual(gpu.utilizationFraction, 0.37)
        XCTAssertEqual(result.clients, [GPUClient(pid: 412, processName: "WindowServer", gpuTimeNanoseconds: 1_000_000_000),
                                        GPUClient(pid: 8120, processName: "ollama", gpuTimeNanoseconds: 5_000_000_000),
                                        GPUClient(pid: 8120, processName: "ollama", gpuTimeNanoseconds: nil)])
    }

    func testDiscreteGPUVRAM() throws {
        let gpu = try XCTUnwrap(IORegGPUParser.parse(try fixture("ioreg_gpu_amd"))?.gpus.first)
        XCTAssertEqual(gpu.name, "AMDRadeonX6000_AMDNavi14GraphicsAccelerator")
        XCTAssertFalse(gpu.unifiedMemory)
        XCTAssertEqual(gpu.vramUsedBytes, 1_073_741_824)
        XCTAssertEqual(gpu.vramTotalBytes, 4_294_967_296)
        XCTAssertEqual(gpu.deviceUtilization, 4)
    }

    func testGarbageIsNil() {
        XCTAssertNil(IORegGPUParser.parse("not a plist"))
    }

    func testPerProcessGPUShare() {
        let before = [GPUClient(pid: 1, processName: "a", gpuTimeNanoseconds: 0), GPUClient(pid: 2, processName: "b", gpuTimeNanoseconds: 10)]
        let after = [GPUClient(pid: 1, processName: "a", gpuTimeNanoseconds: 500_000_000), GPUClient(pid: 1, processName: "a", gpuTimeNanoseconds: nil),
                     GPUClient(pid: 2, processName: "b", gpuTimeNanoseconds: 10), GPUClient(pid: 3, processName: "c", gpuTimeNanoseconds: 5)]
        let usage = GPUClientSampling.usage(current: after, previous: before, interval: 2)
        XCTAssertEqual(usage.map(\.pid), [1, 2, 3])
        XCTAssertEqual(usage[0].gpuPercent ?? -1, 25, accuracy: 0.001)
        XCTAssertEqual(usage[0].connections, 2)
        XCTAssertEqual(usage[1].gpuPercent, 0)
        XCTAssertNil(usage[2].gpuPercent, "a new process has no interval yet")
        XCTAssertTrue(GPUClientSampling.usage(current: after, previous: nil, interval: 0).allSatisfy { $0.gpuPercent == nil })
    }

    func testEnergyToWatts() throws {
        let reading = try XCTUnwrap(EnergyMath.reading(channels: [("CPU Energy", 3000, "mJ"), ("ECPU0", 100, "mJ"), ("GPU Energy", 2_000_000, "uJ"),
                                                                  ("ANE", 500_000_000, "nJ"), ("DRAM", 9, "mJ")], interval: 2))
        XCTAssertEqual(reading.cpuWatts ?? 0, 1.5, accuracy: 0.0001)
        XCTAssertEqual(reading.gpuWatts ?? 0, 1.0, accuracy: 0.0001)
        XCTAssertEqual(reading.neuralEngineWatts ?? 0, 0.25, accuracy: 0.0001)
        XCTAssertEqual(reading.neuralEngineActive, true)
        XCTAssertNil(EnergyMath.reading(channels: [("DRAM", 1, "mJ")], interval: 1))
        XCTAssertNil(EnergyMath.reading(channels: [("CPU Energy", 1, "mJ")], interval: 0))
    }
}

final class GPUServiceTests: XCTestCase {
    private struct FakePower: PowerSampling {
        var unavailableReason: String? = nil
        let reading: PowerReading?
        func sample() -> PowerReading? { reading }
    }

    func testSnapshotFromIoreg() async throws {
        let runner = ScriptedRunner(["-r": ok(try fixture("ioreg_gpu_apple"))])
        let power = PowerReading(cpuWatts: 2, gpuWatts: 3, neuralEngineWatts: 0, intervalSeconds: 1)
        let reader = SystemGPUReader(runner: runner, power: FakePower(reading: power), hasNeuralEngine: true)
        let (snapshot, clients) = try await reader.snapshot(previousClients: nil, interval: 0)
        XCTAssertEqual(snapshot.gpus.count, 1)
        XCTAssertEqual(snapshot.summary, "GPU 37%")
        XCTAssertEqual(snapshot.power, power)
        XCTAssertEqual(snapshot.power?.neuralEngineActive, false)
        XCTAssertNil(snapshot.powerNote)
        XCTAssertEqual(clients.count, 3)
        XCTAssertEqual(snapshot.processes.map(\.pid).sorted(), [412, 8120])
        XCTAssertEqual(runner.calls.first?.1, ["-r", "-d", "2", "-c", "IOAccelerator", "-a", "-w0"])
        XCTAssertEqual(try JSONDecoder().decode(GPUSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
    }

    func testPowerUnavailableIsExplained() async throws {
        let runner = ScriptedRunner(["-r": ok(try fixture("ioreg_gpu_amd"))])
        let reader = SystemGPUReader(runner: runner, power: FakePower(unavailableReason: "Intel Mac", reading: nil), hasNeuralEngine: false)
        let snapshot = try await reader.snapshot(previousClients: nil, interval: 0).0
        XCTAssertEqual(snapshot.powerNote, "Intel Mac")
        XCTAssertFalse(snapshot.hasNeuralEngine)
    }

    func testIoregFailure() async {
        let reader = SystemGPUReader(runner: ScriptedRunner(["-r": failed("boom")]), power: nil, hasNeuralEngine: false)
        do { _ = try await reader.snapshot(previousClients: nil, interval: 0); XCTFail("expected failure") }
        catch { XCTAssertEqual(error as? GPUError, .commandFailed("boom")) }
    }
}
