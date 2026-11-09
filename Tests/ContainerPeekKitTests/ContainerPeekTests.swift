import XCTest
@testable import ContainerPeekKit
import MacPeekCore

final class ContainerParserTests: XCTestCase {
    func testDockerPSFromJSONLines() throws {
        let containers = DockerPSParser.parse(try fixture("docker_ps"))
        XCTAssertEqual(containers.map(\.name), ["shop-db-1", "shop-web-1", "cache"])
        XCTAssertEqual(containers.map(\.state), [.running, .paused, .exited])
        XCTAssertEqual(containers[0].image, "postgres:16")
        XCTAssertEqual(containers[0].composeProject, "shop")
        XCTAssertEqual(containers[0].composeService, "db")
        XCTAssertNil(containers[2].composeProject)
        XCTAssertEqual(containers[0].shortID, "3f4e1d2c9b8a")
        // The IPv6 copy of the same mapping is kept once.
        XCTAssertEqual(containers[0].ports, [PortMapping(hostIP: "0.0.0.0", hostPort: 5432, containerPort: 5432, protocolName: "tcp")])
        XCTAssertEqual(containers[1].ports.map(\.label), ["127.0.0.1:8080 → 80/tcp", "443/tcp (not published)"])
        XCTAssertEqual(containers[1].publishedPorts.count, 1)
        XCTAssertEqual(containers[0].availableActions, [.stop, .restart, .pause])
        XCTAssertEqual(containers[1].availableActions, [.unpause, .stop])
        XCTAssertEqual(containers[2].availableActions, [.start, .remove])
    }

    func testOlderDockerWithoutStateUsesStatusAndRanges() throws {
        let containers = DockerPSParser.parse(try fixture("docker_ps_old"))
        XCTAssertEqual(containers.first?.state, .running)
        XCTAssertEqual(containers.first?.ports, [PortMapping(hostIP: "::", hostPort: 9000, containerPort: 9000, containerPortEnd: 9001, protocolName: "tcp")])
        XCTAssertEqual(containers.first?.ports.first?.label, "*:9000 → 9000-9001/tcp")
        XCTAssertEqual(ContainerState(status: "Exited (137) 2 hours ago"), .exited)
        XCTAssertEqual(ContainerState(status: "Up 3 seconds (Paused)"), .paused)
        XCTAssertEqual(ContainerState(status: "Created"), .created)
    }

    func testDockerStatsAreMergedByFullID() throws {
        let stats = DockerStatsParser.parse(try fixture("docker_stats"))
        let merged = ContainerStatsMerge.merge(DockerPSParser.parse(try fixture("docker_ps")), stats: stats)
        let db = try XCTUnwrap(merged[0].stats)
        XCTAssertEqual(db.cpuPercent, 1.25)
        XCTAssertEqual(db.memoryUsedBytes, 76_021_760)
        XCTAssertEqual(db.memoryLimitBytes, UInt64((7.654 * 1_073_741_824).rounded()))
        XCTAssertEqual(db.memoryPercent, 0.92)
        XCTAssertEqual(db.pids, 7)
        XCTAssertNil(merged[2].stats)
    }

    func testPodmanPSAndShortIDStats() throws {
        let containers = PodmanPSParser.parse(try fixture("podman_ps"))
        XCTAssertEqual(containers.map(\.name), ["api-cache", "hello"])
        XCTAssertEqual(containers[0].ports, [PortMapping(hostIP: nil, hostPort: 6379, containerPort: 6379, protocolName: "tcp")])
        XCTAssertEqual(containers[0].composeProject, "api")
        XCTAssertEqual(containers[1].state, .exited)
        XCTAssertEqual(containers[1].status, "Stopped")
        let merged = ContainerStatsMerge.merge(containers, stats: PodmanStatsParser.parse(try fixture("podman_stats")))
        XCTAssertEqual(merged[0].stats?.memoryUsedBytes, 9_400_000)
        XCTAssertEqual(merged[0].stats?.cpuPercent, 0.35)
        XCTAssertNil(merged[1].stats)
    }

    func testVirtualMachineLists() throws {
        let lima = VMListParser.lima(try fixture("limactl_list"))
        XCTAssertEqual(lima.map(\.name), ["default", "k8s"])
        XCTAssertEqual(lima.map(\.isRunning), [true, false])
        XCTAssertEqual(lima[0].memoryBytes, 4_294_967_296)
        XCTAssertEqual(lima[0].cpus, 4)
        XCTAssertEqual(lima[0].detail, "vz · aarch64")
        let colima = VMListParser.colima(try fixture("colima_list"))
        XCTAssertEqual(colima.first?.detail, "docker · aarch64")
        let tart = VMListParser.tart(try fixture("tart_list"))
        XCTAssertEqual(tart.map(\.isRunning), [true, false])
        XCTAssertEqual(tart[0].diskBytes, 50_000_000_000)
        let parallels = VMListParser.parallels(try fixture("prlctl_list"))
        XCTAssertEqual(parallels.map(\.name), ["Windows 11", "Ubuntu"])
        XCTAssertEqual(parallels.filter(\.isRunning).count, 1)
    }

    func testByteSizes() {
        XCTAssertEqual(ByteSizeText.parse("0B"), 0)
        XCTAssertEqual(ByteSizeText.parse("512kB"), 512_000)
        XCTAssertEqual(ByteSizeText.parse("1.5GiB"), 1_610_612_736)
        XCTAssertEqual(ByteSizeText.parse(" 3 MB "), 3_000_000)
        XCTAssertNil(ByteSizeText.parse("lots"))
        XCTAssertEqual(ByteSizeText.percent("12.5%"), 12.5)
    }

    func testContainerIDValidation() {
        XCTAssertTrue(ContainerID.isValid("3f4e1d2c9b8a"))
        XCTAssertFalse(ContainerID.isValid("--all"))
        XCTAssertFalse(ContainerID.isValid("3f4e1d2c9b8a; rm -rf /"))
        XCTAssertFalse(ContainerID.isValid("short"))
    }

    func testHypervisorProcesses() {
        XCTAssertEqual(VMHostProcessMatcher.kind(of: "com.apple.Virtualization.Virtual"), "Apple Virtualization VM")
        XCTAssertEqual(VMHostProcessMatcher.kind(of: "qemu-system-aarch64"), "QEMU VM")
        XCTAssertNil(VMHostProcessMatcher.kind(of: "Safari"))
        let before = ProcessUsageSnapshot(usages: [ProcessUsage(pid: 10, name: "qemu-system-aarch64", generation: 1, cpuTimeNanoseconds: 1_000_000_000, memoryFootprintBytes: 1)], unreadable: 0)
        let after = ProcessUsageSnapshot(usages: [ProcessUsage(pid: 10, name: "qemu-system-aarch64", generation: 1, cpuTimeNanoseconds: 3_000_000_000, memoryFootprintBytes: 2_000_000_000),
                                                  ProcessUsage(pid: 11, name: "Finder", cpuTimeNanoseconds: 0, memoryFootprintBytes: 1)], unreadable: 0)
        let hosts = VMHostSampling.hosts(current: after, previous: before, interval: 2)
        XCTAssertEqual(hosts.map(\.pid), [10])
        XCTAssertEqual(try XCTUnwrap(hosts.first?.cpuPercent), 100, accuracy: 0.001)
        XCTAssertNil(VMHostSampling.hosts(current: after, previous: nil, interval: 0).first?.cpuPercent)
    }
}

final class ContainerServiceTests: XCTestCase {
    private func tools(docker: Bool = true, podman: Bool = false, lima: Bool = false) -> ContainerToolLocators {
        func locator(_ path: String, _ present: Bool) -> ExecutableLocator { ExecutableLocator(candidates: [path], isExecutable: { _ in present }) }
        return ContainerToolLocators(docker: locator("/usr/local/bin/docker", docker), podman: locator("/opt/homebrew/bin/podman", podman),
                                     limactl: locator("/opt/homebrew/bin/limactl", lima), colima: locator("/x/colima", false),
                                     tart: locator("/x/tart", false), prlctl: locator("/x/prlctl", false))
    }

    func testSnapshotListsContainersStatsAndVMs() async throws {
        let runner = ScriptedRunner(["ps": ok(try fixture("docker_ps")), "stats": ok(try fixture("docker_stats")),
                                     "context": ok("orbstack\n"), "list": ok(try fixture("limactl_list"))])
        let reader = SystemContainerReader(runner: runner, tools: tools(lima: true))
        let snapshot = try await reader.snapshot()
        XCTAssertEqual(snapshot.engines.count, 1)
        XCTAssertEqual(snapshot.engines[0].context, "orbstack")
        XCTAssertEqual(snapshot.engines[0].status, .running)
        XCTAssertEqual(snapshot.runningContainers, 1)
        XCTAssertEqual(snapshot.allContainers[0].stats?.pids, 7)
        XCTAssertEqual(snapshot.virtualMachines.count, 2)
        XCTAssertEqual(snapshot.summary, "1 container, 1 VM running")
        // Fixed argument lists, never a shell.
        XCTAssertTrue(runner.calls.contains { $0.0 == "/usr/local/bin/docker" && $0.1 == ["ps", "--all", "--no-trunc", "--format", "{{json .}}"] })
    }

    func testDaemonNotRunningIsNotAnError() async throws {
        let runner = ScriptedRunner(["ps": failed("Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?"),
                                     "context": ok("default")])
        let snapshot = try await SystemContainerReader(runner: runner, tools: tools()).snapshot()
        guard case .notRunning = snapshot.engines.first?.status else { return XCTFail("expected notRunning") }
        XCTAssertTrue(snapshot.allContainers.isEmpty)
    }

    func testNothingInstalled() async throws {
        let snapshot = try await SystemContainerReader(runner: ScriptedRunner([:]), tools: tools(docker: false)).snapshot()
        XCTAssertTrue(snapshot.nothingInstalled)
        XCTAssertEqual(snapshot.summary, "No engines found")
    }

    func testActionRevalidatesAndRunsOneFixedCommand() async throws {
        let all = DockerPSParser.parse(try fixture("docker_ps"))
        let db = all[0]
        let line = try fixture("docker_ps").split(separator: "\n").first.map(String.init) ?? ""
        let runner = ScriptedRunner(["ps": ok(line), "stop": ok(db.id)])
        let result = await SystemContainerController(runner: runner, tools: tools()).perform(.stop, on: db, engine: .docker)
        XCTAssertEqual(result, .done)
        XCTAssertEqual(runner.calls.last?.1, ["stop", db.id])
        XCTAssertEqual(runner.calls.first?.1, ["ps", "--all", "--no-trunc", "--filter", "id=\(db.id)", "--format", "{{json .}}"])
    }

    func testActionRefusesAGoneRenamedOrWrongStateContainer() async throws {
        let db = DockerPSParser.parse(try fixture("docker_ps"))[0]
        let line = try fixture("docker_ps").split(separator: "\n").first.map(String.init) ?? ""
        let gone = await SystemContainerController(runner: ScriptedRunner(["ps": ok("")]), tools: tools()).perform(.stop, on: db, engine: .docker)
        XCTAssertEqual(gone, .changed("shop-db-1 no longer exists."))
        let runner = ScriptedRunner(["ps": ok(line)])
        let wrongState = await SystemContainerController(runner: runner, tools: tools()).perform(.start, on: db, engine: .docker)
        XCTAssertEqual(wrongState, .changed("shop-db-1 is running, so it cannot be started."))
        XCTAssertFalse(runner.calls.contains { $0.1.first == "start" })
        let renamed = ContainerInfo(id: db.id, name: "other", image: db.image, state: db.state, status: db.status, ports: [],
                                    composeProject: nil, composeService: nil, createdAt: nil)
        let result = await SystemContainerController(runner: ScriptedRunner(["ps": ok(line)]), tools: tools()).perform(.stop, on: renamed, engine: .docker)
        XCTAssertEqual(result, .changed("the container is now called shop-db-1."))
        let invalid = ContainerInfo(id: "--rm", name: "x", image: "", state: .running, status: "", ports: [], composeProject: nil,
                                    composeService: nil, createdAt: nil)
        let refused = await SystemContainerController(runner: ScriptedRunner([:]), tools: tools()).perform(.stop, on: invalid, engine: .docker)
        XCTAssertEqual(refused, .changed("that is not a container ID."))
    }

    func testLogsKeepTheLastLines() async throws {
        let db = DockerPSParser.parse(try fixture("docker_ps"))[0]
        let runner = ScriptedRunner(["logs": .success(CommandOutput(stdout: "one\ntwo\nthree\n", stderr: "warn\n", status: 0))])
        let logs = try await SystemContainerReader(runner: runner, tools: tools()).logs(of: db, engine: .docker, lines: 3)
        XCTAssertEqual(logs.lines, ["two", "three", "warn"])
        XCTAssertTrue(logs.truncated)
        XCTAssertEqual(runner.calls.first?.1, ["logs", "--tail", "3", db.id])
    }

    func testSnapshotRoundTrips() throws {
        let containers = ContainerStatsMerge.merge(DockerPSParser.parse(try fixture("docker_ps")), stats: DockerStatsParser.parse(try fixture("docker_stats")))
        let snapshot = ContainerSnapshot(
            engines: [ContainerEngineReport(kind: .docker, executable: "/usr/local/bin/docker", context: "orbstack", status: .running, containers: containers, statsNote: nil),
                      ContainerEngineReport(kind: .podman, executable: "/opt/homebrew/bin/podman", context: nil, status: .notRunning("off"), containers: [], statsNote: nil)],
            virtualMachines: VMListParser.lima(try fixture("limactl_list")),
            vmProcesses: [VMHostProcess(pid: 3, name: "qemu-system-aarch64", kind: "QEMU VM", cpuPercent: 3.5, memoryFootprintBytes: 10)],
            notes: ["Tart did not answer."])
        XCTAssertEqual(try JSONDecoder().decode(ContainerSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
        let other = ContainerState.other("weird")
        XCTAssertEqual(try JSONDecoder().decode(ContainerState.self, from: JSONEncoder().encode(other)), other)
    }
}

final class ContainerQuickSnapshotTests: XCTestCase {
    func testQuickSnapshotNeverRunsStats() async throws {
        let runner = ScriptedRunner(["ps": ok(try fixture("docker_ps")), "context": ok("default")])
        let tools = ContainerToolLocators(docker: ExecutableLocator(candidates: ["/d"], isExecutable: { _ in true }),
                                          podman: ExecutableLocator(candidates: []), limactl: ExecutableLocator(candidates: []),
                                          colima: ExecutableLocator(candidates: []), tart: ExecutableLocator(candidates: []),
                                          prlctl: ExecutableLocator(candidates: []))
        let reader: ContainerReading = SystemContainerReader(runner: runner, tools: tools)
        let snapshot = try await reader.quickSnapshot()
        XCTAssertEqual(snapshot.runningContainers, 1)
        XCTAssertNil(snapshot.allContainers[0].stats)
        XCTAssertFalse(runner.calls.contains { $0.1.first == "stats" })
    }
}
