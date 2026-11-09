import XCTest
import MacPeekCore
import CPUPeekKit
import ProcessPeekKit
import DNSPeekKit
import NetPeekKit
import USBPeekKit
import ContainerPeekKit
import GPUPeekKit
import ModelPeekKit
import RemoteCrypto
import RemoteProtocol
@testable import RemoteAgent

/// The operations added for ContainerPeek, GPUPeek, ModelPeek and the NetPeek/DNSPeek/USBPeek/ProcessPeek extensions.
final class NewPeeksAgentTests: XCTestCase {
    private struct Unreadable: Error {}

    private actor Calls {
        private(set) var actions: [String] = []
        func add(_ value: String) { actions.append(value) }
    }

    private static let entry = ProcessEntry(pid: 500, ppid: 1, uid: Int(getuid()), user: "me", state: "S",
                                            startTime: Date(timeIntervalSince1970: 1_700_000_000), elapsed: "01:00",
                                            cpuPercent: 0, residentKB: 10, executable: "node")
    private static let container = ContainerInfo(id: String(repeating: "a", count: 64), name: "web", image: "nginx", state: .running,
                                                 status: "Up", ports: [], composeProject: nil, composeService: nil, createdAt: nil)
    private static let gpuSnapshot = GPUSnapshot(gpus: [], processes: [], power: PowerReading(cpuWatts: 1, gpuWatts: 2, neuralEngineWatts: 0, intervalSeconds: 1),
                                                 powerNote: nil, hasNeuralEngine: true)

    private func handler(_ calls: Calls) -> RequestHandler {
        let entry = Self.entry
        let readers = AgentReaders(
            device: { DeviceInfo(computerName: "Studio", localHostName: "studio", modelIdentifier: nil, macOSVersion: "15.1", bootTime: nil) },
            cpuTopology: { CPUTopology(chip: "M2", logicalCores: 8, groups: []) },
            cpuSnapshot: { throw Unreadable() }, memory: { throw Unreadable() }, processUsage: { throw Unreadable() },
            volumes: { throw Unreadable() }, networkCounters: { throw Unreadable() }, networkSnapshot: { throw Unreadable() },
            ports: { [] }, processes: { ProcessSnapshot(entries: [entry]) }, sleep: { throw Unreadable() },
            networkExtras: { NetExtras(proxy: nil, vpns: [], tailscale: nil, tailscaleNote: nil, preferredWiFi: ["Home"]) },
            dnsOverrides: { DNSOverrides(hostsEntries: [], hostsNote: nil, resolverFiles: [], resolverNote: nil) },
            bluetooth: { BluetoothReport(poweredOn: true, devices: []) },
            processOrigin: { _, _ in ProcessOrigin(kind: .other, job: nil, details: nil, viaPID: nil) },
            openFiles: { process in OpenFilesReport(pid: process.pid, files: [OpenFile(descriptor: "cwd", type: "DIR", name: "/tmp")], truncated: false, note: nil) },
            containers: { ContainerSnapshot(engines: [], virtualMachines: [], vmProcesses: [], notes: []) },
            gpu: { Self.gpuSnapshot },
            models: { ModelSnapshot(runners: []) })
        let actions = AgentActions(freePort: { _, _ in .terminated }, quitProcess: { _, _ in .terminated },
                                   containerAction: { action, container, _ in
                                       await calls.add("\(action.rawValue) \(container.name)")
                                       return .done
                                   })
        return RequestHandler(readers: readers, actions: actions, agentVersion: "0.4.0")
    }

    private func console(_ role: ConsoleRole) -> PairedConsole {
        PairedConsole(identity: DeviceIdentity(name: "Laptop").publicIdentity, role: role, pairedAt: Date())
    }

    private let allowed = RemoteSettings(isEnabled: true, allowActions: true)

    func testNewReadsAreAnsweredAndAdvertised() async throws {
        let handler = handler(Calls())
        let capabilities = try await handler.handle(.request(.capabilities), from: console(.viewOnly), settings: allowed)
            .response.body(Capabilities.self)
        for operation in [Operation.networkExtras, .dnsOverrides, .bluetooth, .processOrigin, .processOpenFiles, .containers, .gpu, .models, .containerAction] {
            XCTAssertTrue(capabilities.operations.contains(operation), operation.rawValue)
        }
        let extras = try await handler.handle(.request(.networkExtras), from: console(.viewOnly), settings: allowed).response.body(NetExtras.self)
        XCTAssertEqual(extras.preferredWiFi, ["Home"])
        let gpu = try await handler.handle(.request(.gpu), from: console(.viewOnly), settings: allowed).response.body(GPUSnapshot.self)
        XCTAssertEqual(gpu, Self.gpuSnapshot)
        _ = try await handler.handle(.request(.containers), from: console(.viewOnly), settings: allowed).response.body(ContainerSnapshot.self)
        _ = try await handler.handle(.request(.models), from: console(.viewOnly), settings: allowed).response.body(ModelSnapshot.self)
        _ = try await handler.handle(.request(.dnsOverrides), from: console(.viewOnly), settings: allowed).response.body(DNSOverrides.self)
        _ = try await handler.handle(.request(.bluetooth), from: console(.viewOnly), settings: allowed).response.body(BluetoothReport.self)
    }

    func testProcessOriginOnlyForTheSameProcess() async throws {
        let handler = handler(Calls())
        let report = try await handler.handle(try .request(.processOrigin, body: ProcessRequest(process: Self.entry)), from: console(.viewOnly),
                                              settings: allowed).response.body(ProcessOriginReport.self)
        XCTAssertEqual(report.origin.kind, .other)
        XCTAssertFalse(report.advice.reasons.isEmpty)
        let files = try await handler.handle(try .request(.processOpenFiles, body: ProcessRequest(process: Self.entry)), from: console(.viewOnly),
                                             settings: allowed).response.body(OpenFilesReport.self)
        XCTAssertEqual(files.workingDirectory, "/tmp")

        let reused = ProcessEntry(pid: 500, ppid: 1, uid: 501, user: "me", state: "S", startTime: Date(timeIntervalSince1970: 1_800_000_000),
                                  elapsed: "00:01", cpuPercent: 0, residentKB: 1, executable: "other")
        let refused = await handler.handle(try .request(.processOpenFiles, body: ProcessRequest(process: reused)), from: console(.viewOnly),
                                           settings: allowed).response
        XCTAssertEqual(refused.kind, .error)
        XCTAssertEqual(try refused.body(RemoteError.self).code, .unavailable)
    }

    func testContainerActionIsGatedLikeOtherActions() async throws {
        let calls = Calls()
        let handler = handler(calls)
        let request = try Envelope.request(.containerAction, body: ContainerActionRequest(action: .stop, container: Self.container, engine: .docker))

        let viewOnly = await handler.handle(request, from: console(.viewOnly), settings: allowed)
        XCTAssertEqual(try viewOnly.response.body(RemoteError.self).code, .notPermitted)
        XCTAssertEqual(viewOnly.record?.outcome.hasPrefix("Refused"), true)

        let off = await handler.handle(request, from: console(.viewAndAct), settings: RemoteSettings(isEnabled: true, allowActions: false))
        XCTAssertEqual(try off.response.body(RemoteError.self).code, .actionsDisabled)
        let none = await calls.actions
        XCTAssertTrue(none.isEmpty)

        let done = await handler.handle(request, from: console(.viewAndAct), settings: allowed)
        XCTAssertEqual(try done.response.body(ContainerActionResponse.self).result, .done)
        XCTAssertEqual(done.record?.event, "Stop container web (Docker)")
        XCTAssertEqual(done.record?.outcome, "Done")
        let performed = await calls.actions
        XCTAssertEqual(performed, ["stop web"])

        let bad = ContainerInfo(id: "--force", name: "x", image: "", state: .running, status: "", ports: [], composeProject: nil,
                                composeService: nil, createdAt: nil)
        let invalid = await handler.handle(try .request(.containerAction, body: ContainerActionRequest(action: .remove, container: bad, engine: .docker)),
                                           from: console(.viewAndAct), settings: allowed)
        XCTAssertEqual(try invalid.response.body(RemoteError.self).code, .invalidPayload)
        let after = await calls.actions
        XCTAssertEqual(after.count, 1)
    }

    func testIntervalSamplerPassesThePreviousState() async throws {
        let sampler = IntervalSampler<Int, String>(initial: 0) { previous, interval in
            ("\(previous)/\(interval > 0)", previous + 1)
        }
        let first = try await sampler.read()
        let second = try await sampler.read()
        XCTAssertEqual(first, "0/false")
        XCTAssertEqual(second, "1/true")
    }
}
