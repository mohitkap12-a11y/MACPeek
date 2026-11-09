import XCTest
@testable import ModelPeekKit
import GPUPeekKit
import MacPeekCore

final class ModelParserTests: XCTestCase {
    private func lines() throws -> [ProcessLine] { ProcessLineParser.parse(comm: try fixture("ps_comm"), args: try fixture("ps_args")) }

    func testRunnersAreRecognised() throws {
        let matches = try lines().compactMap { line in RunnerMatcher.match(line).map { (line.pid, $0.kind, $0.role) } }
        XCTAssertEqual(matches.map(\.0), [612, 640, 8120, 701, 702, 930, 1001, 1100, 1200])
        XCTAssertEqual(matches.first { $0.0 == 640 }?.2, "server")
        XCTAssertEqual(matches.first { $0.0 == 8120 }?.2, "model runner")
        XCTAssertEqual(matches.first { $0.0 == 701 }?.1, .lmStudio)
        XCTAssertEqual(matches.first { $0.0 == 930 }?.1, .lmStudio)
        XCTAssertEqual(matches.first { $0.0 == 1001 }?.1, .mlx)
        XCTAssertEqual(matches.first { $0.0 == 1001 }?.2, "server")
        XCTAssertEqual(matches.first { $0.0 == 1100 }?.1, .llamaCpp)
        XCTAssertEqual(matches.first { $0.0 == 1200 }?.1, .llamafile)
    }

    func testModelArgumentsNeverIncludeOtherArguments() throws {
        let byPID = Dictionary(try lines().map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(RunnerMatcher.modelArgument(byPID[1001]!), "mlx-community/Qwen2.5-7B-Instruct-4bit")
        XCTAssertEqual(RunnerMatcher.modelArgument(byPID[1100]!), "gemma-3-4b-it-Q4_K_M.gguf")
        XCTAssertNil(RunnerMatcher.modelArgument(byPID[8120]!), "Ollama blobs are named by the API instead")
        XCTAssertNil(RunnerMatcher.modelArgument(ProcessLine(pid: 1, ppid: 0, command: "llama-cli", arguments: "llama-cli -m")))
        XCTAssertEqual(RunnerMatcher.modelArgument(ProcessLine(pid: 1, ppid: 0, command: "llama-server", arguments: "llama-server --model=/a/b/c.gguf")), "c.gguf")
    }

    func testOllamaPS() throws {
        let models = try XCTUnwrap(OllamaPSParser.parse(Data(try fixture("ollama_ps").utf8)))
        XCTAssertEqual(models.map(\.name), ["llama3.2:latest", "qwen2.5:32b"])
        XCTAssertEqual(models[0].sizeBytes, 3_972_526_080)
        XCTAssertEqual(models[0].contextLength, 8192)
        XCTAssertEqual(models[0].quantization, "Q4_K_M")
        XCTAssertEqual(models[0].parameterSize, "3.2B")
        XCTAssertEqual(models[0].processorSplit, "100% GPU")
        XCTAssertEqual(models[1].processorSplit, "50% GPU / 50% CPU")
        XCTAssertEqual(OllamaPSParser.parse(Data(#"{"models":[]}"#.utf8)), [])
        XCTAssertNil(OllamaPSParser.parse(Data("<html>".utf8)))
    }

    func testLMStudioOnlyLoadedModels() throws {
        let models = try XCTUnwrap(LMStudioModelsParser.parse(Data(try fixture("lmstudio_models").utf8)))
        XCTAssertEqual(models.map(\.name), ["qwen2.5-7b-instruct"])
        XCTAssertEqual(models[0].contextLength, 4096)
        XCTAssertEqual(models[0].family, "qwen2")
    }
}

final class ModelServiceTests: XCTestCase {
    private final class FakeAPI: LocalAPIFetching, @unchecked Sendable {
        var responses: [Int: Data] = [:]
        var asked: [String] = []
        func get(port: Int, path: String) async throws -> Data {
            asked.append("\(port)\(path)")
            guard let data = responses[port] else { throw URLError(.cannotConnectToHost) }
            return data
        }
    }

    private struct FakeUsage: ProcessUsageReading {
        let snapshot: ProcessUsageSnapshot
        func read(isCancelled: @Sendable () -> Bool) throws -> ProcessUsageSnapshot { snapshot }
    }

    private struct FakeGPU: GPUReading {
        let list: [GPUClient]
        func snapshot(previousClients: [GPUClient]?, interval: TimeInterval) async throws -> (GPUSnapshot, [GPUClient]) {
            (GPUSnapshot(gpus: [], processes: [], power: nil, powerNote: nil, hasNeuralEngine: false), list)
        }
        func clients() async throws -> [GPUClient] { list }
        func gpus() async throws -> [GPUInfo] { [] }
    }

    private func runner() throws -> ScriptedRunner {
        let comm = try fixture("ps_comm"), args = try fixture("ps_args")
        return ScriptedRunner(["-axo": ok(comm), "-ww": ok(args)])
    }

    func testSnapshotGroupsProcessesAndAsksOnlyLoopbackAPIs() async throws {
        let api = FakeAPI()
        api.responses[11434] = Data(try fixture("ollama_ps").utf8)
        let usage = FakeUsage(snapshot: ProcessUsageSnapshot(usages: [
            ProcessUsage(pid: 640, name: "ollama", generation: 1, cpuTimeNanoseconds: 1_000_000_000, memoryFootprintBytes: 100),
            ProcessUsage(pid: 8120, name: "ollama", generation: 2, cpuTimeNanoseconds: 4_000_000_000, memoryFootprintBytes: 4_000_000_000),
        ], unreadable: 0))
        let scripted = try runner()
        let reader = SystemModelReader(runner: scripted, api: api, usage: usage,
                                       gpu: FakeGPU(list: [GPUClient(pid: 8120, processName: "ollama", gpuTimeNanoseconds: 3_000_000_000)]))
        let previous = ModelSamplingState(
            usage: ProcessUsageSnapshot(usages: [ProcessUsage(pid: 8120, name: "ollama", generation: 2, cpuTimeNanoseconds: 2_000_000_000, memoryFootprintBytes: 1)], unreadable: 0),
            gpuClients: [GPUClient(pid: 8120, processName: "ollama", gpuTimeNanoseconds: 2_000_000_000)],
            date: Date().addingTimeInterval(-2))
        let (snapshot, state) = try await reader.snapshot(previous: previous)
        XCTAssertEqual(snapshot.runners.map(\.kind), [.ollama, .lmStudio, .mlx, .llamaCpp, .llamafile])
        let ollama = snapshot.runners[0]
        XCTAssertEqual(ollama.models.map(\.name), ["llama3.2:latest", "qwen2.5:32b"])
        XCTAssertEqual(ollama.memoryFootprintBytes, 4_000_000_100)
        XCTAssertEqual(ollama.processes.first?.pid, 8120)
        XCTAssertEqual(try XCTUnwrap(ollama.processes.first?.cpuPercent), 100, accuracy: 2)
        XCTAssertEqual(try XCTUnwrap(ollama.gpuPercent), 50, accuracy: 2)
        XCTAssertNotNil(snapshot.runners[1].note, "LM Studio's server is off")
        XCTAssertEqual(snapshot.runners[2].models, [LoadedModel(name: "mlx-community/Qwen2.5-7B-Instruct-4bit", source: .commandLine)])
        XCTAssertEqual(snapshot.runners[3].models.map(\.name), ["gemma-3-4b-it-Q4_K_M.gguf"])
        XCTAssertEqual(snapshot.summary, "4 models loaded")
        XCTAssertEqual(Set(api.asked), ["11434/api/ps", "1234/api/v0/models"])
        XCTAssertEqual(state.gpuClients?.count, 1)
        // Only candidate runners' command lines are asked for: not launchd (1) or the shell (1400).
        let asked = try XCTUnwrap(scripted.calls.first { $0.1.first == "-ww" }?.1.last).split(separator: ",").map(String.init)
        XCTAssertEqual(asked, ["612", "640", "8120", "701", "702", "930", "1001", "1100", "1200", "1300"])
        // Nothing from a command line other than the model name ends up in the snapshot (llama-server had --api-key).
        let encoded = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        XCTAssertFalse(encoded.contains("sk-secret"))
        XCTAssertEqual(try JSONDecoder().decode(ModelSnapshot.self, from: Data(encoded.utf8)), snapshot)
    }

    func testNoRunnersAsksNoAPI() async throws {
        let api = FakeAPI()
        let runner = ScriptedRunner(["-axo": ok("    1     0 /sbin/launchd\n    7     1 /bin/zsh\n")])
        let reader = SystemModelReader(runner: runner, api: api)
        let snapshot = try await reader.snapshot()
        XCTAssertEqual(runner.calls.count, 1, "no command line is read when no process could be a runner")
        XCTAssertTrue(snapshot.runners.isEmpty)
        XCTAssertEqual(snapshot.summary, "No runners")
        XCTAssertTrue(api.asked.isEmpty)
    }

    func testPSFailure() async {
        let reader = SystemModelReader(runner: ScriptedRunner(["-axo": failed("nope")]), api: FakeAPI())
        do { _ = try await reader.snapshot(); XCTFail("expected failure") }
        catch { XCTAssertEqual(error as? ModelError, .commandFailed("nope")) }
    }
}
