import XCTest
import MacPeekCore
@testable import ContainerPeekKit

/// Answers by the whole argument list (the first word alone cannot tell `image ls` from `image rm`) and records every call.
final class ArgumentRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [[String]] = []
    private let answers: [[String]: Result<CommandOutput, Error>]
    init(_ answers: [[String]: Result<CommandOutput, Error>]) { self.answers = answers }
    var calls: [[String]] { lock.lock(); defer { lock.unlock() }; return _calls }
    func run(_ executable: String, _ arguments: [String]) async throws -> CommandOutput {
        lock.lock(); _calls.append(arguments); lock.unlock()
        return try (answers[arguments] ?? .success(CommandOutput(stdout: "", stderr: "unscripted", status: 1))).get()
    }
}

final class ImageTests: XCTestCase {
    private let list = ["image", "ls", "--no-trunc", "--format", "{{json .}}"]
    private let ps = ["ps", "--all", "--no-trunc", "--format", "{{json .}}"]

    private func tools(docker: Bool = true) -> ContainerToolLocators {
        func locator(_ path: String, _ present: Bool) -> ExecutableLocator { ExecutableLocator(candidates: [path], isExecutable: { _ in present }) }
        return ContainerToolLocators(docker: locator("/usr/local/bin/docker", docker), podman: locator("/x/podman", false),
                                     limactl: locator("/x/limactl", false), colima: locator("/x/colima", false),
                                     tart: locator("/x/tart", false), prlctl: locator("/x/prlctl", false))
    }

    func testParsesImagesAndTreatsNoneAsMissing() throws {
        let images = DockerImagesParser.parse(try fixture("docker_images"))
        XCTAssertEqual(images.count, 4)
        XCTAssertEqual(images[0].reference, "postgres:16")
        XCTAssertEqual(images[0].imageID, "b1c2d3e4f5a60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90")
        XCTAssertEqual(images[0].sizeBytes, 432_000_000)
        XCTAssertEqual(images[0].createdSince, "6 weeks ago")
        // One image with two tags is two rows.
        XCTAssertEqual(images[1].imageID, images[2].imageID)
        XCTAssertEqual([images[1].reference, images[2].reference], ["nginx:1.25", "nginx:latest"])
        // Untagged: no reference, removed by its ID.
        XCTAssertTrue(images[3].isDangling)
        XCTAssertNil(images[3].reference)
        XCTAssertEqual(images[3].target, images[3].imageID)
        XCTAssertEqual(images[3].sizeBytes, 1_240_000_000)
        XCTAssertEqual(images[0].target, "postgres:16")
    }

    func testUsageMatchesNamesLatestAndIDPrefixes() throws {
        let images = DockerImagesParser.parse(try fixture("docker_images"))
        let containers = DockerPSParser.parse(try fixture("docker_ps"))
        let used = ImageUsage.apply(to: images, containers: containers)
        XCTAssertEqual(used[0].usedBy, ["shop-db-1"])
        XCTAssertTrue(used[1].usedBy.isEmpty) // nginx:1.27 is another image
        func container(_ image: String) -> ContainerInfo {
            ContainerInfo(id: String(repeating: "a", count: 64), name: "c", image: image, state: .running, status: "Up", ports: [],
                          composeProject: nil, composeService: nil, createdAt: nil)
        }
        XCTAssertEqual(ImageUsage.apply(to: [images[2]], containers: [container("nginx")])[0].usedBy, ["c"])
        XCTAssertTrue(ImageUsage.apply(to: [images[1]], containers: [container("nginx")])[0].usedBy.isEmpty)
        XCTAssertEqual(ImageUsage.apply(to: [images[3]], containers: [container("deadbeef0011")])[0].usedBy, ["c"])
    }

    func testReaderListsImagesWithUsageAndSortsUntaggedLast() async throws {
        let runner = ArgumentRunner([["context", "show"]: ok("desktop-linux"), list: ok(try fixture("docker_images")),
                                     ps: ok(try fixture("docker_ps"))])
        let snapshot = try await SystemImageReader(runner: runner, tools: tools()).snapshot()
        XCTAssertEqual(snapshot.status, .running)
        XCTAssertEqual(snapshot.context, "desktop-linux")
        XCTAssertEqual(snapshot.images.map(\.displayName), ["nginx:1.25", "nginx:latest", "postgres:16", "untagged"])
        XCTAssertEqual(snapshot.inUseCount, 1)
        XCTAssertEqual(try JSONDecoder().decode(ImageSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
    }

    func testReaderReportsMissingAndStoppedDocker() async throws {
        let missing = try await SystemImageReader(runner: ArgumentRunner([:]), tools: tools(docker: false)).snapshot()
        XCTAssertEqual(missing.status, .failed("Docker is not installed in a location MacPeek checks."))
        let stopped = ArgumentRunner([list: .success(CommandOutput(stdout: "", stderr: "Cannot connect to the Docker daemon at unix:///x.sock", status: 1))])
        let snapshot = try await SystemImageReader(runner: stopped, tools: tools()).snapshot()
        if case .notRunning = snapshot.status {} else { XCTFail("expected notRunning, got \(snapshot.status)") }
    }

    func testRemoveDeletesOnlyTheTagTheyChose() async throws {
        let images = DockerImagesParser.parse(try fixture("docker_images"))
        let runner = ArgumentRunner([list: ok(try fixture("docker_images")), ["image", "rm", "nginx:latest"]: ok("Untagged: nginx:latest")])
        let result = await SystemImageController(runner: runner, tools: tools()).remove(images[2])
        XCTAssertEqual(result, .done)
        XCTAssertEqual(runner.calls.last, ["image", "rm", "nginx:latest"])
        XCTAssertFalse(runner.calls.contains { $0.contains("--force") || $0.contains("-f") })
    }

    func testRemoveUntaggedImageUsesItsID() async throws {
        let images = DockerImagesParser.parse(try fixture("docker_images"))
        let runner = ArgumentRunner([list: ok(try fixture("docker_images")), ["image", "rm", images[3].imageID]: ok("Deleted: sha256:x")])
        let result = await SystemImageController(runner: runner, tools: tools()).remove(images[3])
        XCTAssertEqual(result, .done)
    }

    func testRemoveShowsDockersRefusalAndRefusesGoneOrChangedImages() async throws {
        let images = DockerImagesParser.parse(try fixture("docker_images"))
        let busy = ArgumentRunner([list: ok(try fixture("docker_images")),
                                   ["image", "rm", "postgres:16"]: .success(CommandOutput(stdout: "", stderr: "Error response from daemon: conflict: unable to delete b1c2d3e4f5a6 (must be forced) - container 3f4e1d2c9b8a is using its referenced image\n", status: 1))])
        let refused = await SystemImageController(runner: busy, tools: tools()).remove(images[0])
        XCTAssertEqual(refused, .failed("Error response from daemon: conflict: unable to delete b1c2d3e4f5a6 (must be forced) - container 3f4e1d2c9b8a is using its referenced image"))

        let gone = ArgumentRunner([list: ok("")])
        let missing = await SystemImageController(runner: gone, tools: tools()).remove(images[0])
        XCTAssertEqual(missing, .changed("postgres:16 no longer exists, or is now a different image."))
        XCTAssertFalse(gone.calls.contains { $0.first == "image" && $0[1] == "rm" })

        // Same tag, different image behind it: not the image the person saw.
        let moved = ImageInfo(imageID: String(repeating: "1", count: 64), repository: "postgres", tag: "16", sizeText: "1MB", sizeBytes: 1,
                              createdSince: nil, createdAt: nil)
        let other = ArgumentRunner([list: ok(try fixture("docker_images"))])
        let changed = await SystemImageController(runner: other, tools: tools()).remove(moved)
        if case .changed = changed {} else { XCTFail("expected changed, got \(changed)") }
    }

    func testRefusesAnythingThatCouldBeReadAsAnOption() async throws {
        let bad = ImageInfo(imageID: "--force", repository: "x", tag: "y", sizeText: "", sizeBytes: nil, createdSince: nil, createdAt: nil)
        let runner = ArgumentRunner([:])
        let controller = SystemImageController(runner: runner, tools: tools())
        let removed = await controller.remove(bad)
        XCTAssertEqual(removed, .failed("That is not an image ID."))
        let named = ImageInfo(imageID: String(repeating: "a", count: 64), repository: "--privileged", tag: "x", sizeText: "", sizeBytes: nil,
                              createdSince: nil, createdAt: nil)
        let ran = await controller.run(named, options: ContainerRunOptions())
        XCTAssertEqual(ran, .failed("That is not an image name."))
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testRunArgumentsAreFixedAndPortsStayOnThisMacByDefault() throws {
        let image = DockerImagesParser.parse(try fixture("docker_images"))[0]
        let local = ContainerRunOptions(name: "db", ports: [RunPort(hostPort: 5433, containerPort: 5432)])
        XCTAssertEqual(SystemImageController.runArguments(image: image, options: local),
                       ["run", "--detach", "--pull", "never", "--name", "db", "--publish", "127.0.0.1:5433:5432/tcp", "postgres:16"])
        let open = ContainerRunOptions(ports: [RunPort(hostPort: 8080, containerPort: 80, protocolName: "udp")], exposeToNetwork: true)
        XCTAssertEqual(SystemImageController.runArguments(image: image, options: open),
                       ["run", "--detach", "--pull", "never", "--publish", "8080:80/udp", "postgres:16"])
        XCTAssertEqual(SystemImageController.runArguments(image: image, options: ContainerRunOptions()),
                       ["run", "--detach", "--pull", "never", "postgres:16"])
    }

    func testRunStartsAContainerAndReturnsItsID() async throws {
        let image = DockerImagesParser.parse(try fixture("docker_images"))[0]
        let id = String(repeating: "e", count: 64)
        let options = ContainerRunOptions(name: "db", ports: [RunPort(hostPort: 5433, containerPort: 5432)])
        let args = SystemImageController.runArguments(image: image, options: options)
        let runner = ArgumentRunner([list: ok(try fixture("docker_images")), args: ok(id + "\n")])
        let result = await SystemImageController(runner: runner, tools: tools()).run(image, options: options)
        XCTAssertEqual(result, .started(containerID: id))
        XCTAssertEqual(runner.calls.last, args)

        let failing = ArgumentRunner([list: ok(try fixture("docker_images")),
                                      args: .success(CommandOutput(stdout: "", stderr: "docker: Error response from daemon: Conflict. The container name \"/db\" is already in use\n", status: 125))])
        let failed = await SystemImageController(runner: failing, tools: tools()).run(image, options: options)
        XCTAssertEqual(failed, .failed("docker: Error response from daemon: Conflict. The container name \"/db\" is already in use"))
    }

    func testRunOptionsAreValidated() {
        func problem(_ options: ContainerRunOptions) -> String? { ImageReference.problem(with: options) }
        XCTAssertNil(problem(ContainerRunOptions(name: "web-1", ports: [RunPort(hostPort: 80, containerPort: 80)])))
        XCTAssertNotNil(problem(ContainerRunOptions(name: "--privileged")))
        XCTAssertNotNil(problem(ContainerRunOptions(name: "a b")))
        XCTAssertNotNil(problem(ContainerRunOptions(ports: [RunPort(hostPort: 0, containerPort: 80)])))
        XCTAssertNotNil(problem(ContainerRunOptions(ports: [RunPort(hostPort: 80, containerPort: 70000)])))
        XCTAssertNotNil(problem(ContainerRunOptions(ports: [RunPort(hostPort: 80, containerPort: 80, protocolName: "sctp")])))
        XCTAssertNotNil(problem(ContainerRunOptions(ports: [RunPort(hostPort: 80, containerPort: 80), RunPort(hostPort: 80, containerPort: 81)])))
        XCTAssertNil(problem(ContainerRunOptions(ports: [RunPort(hostPort: 53, containerPort: 53), RunPort(hostPort: 53, containerPort: 53, protocolName: "udp")])))
        XCTAssertNotNil(problem(ContainerRunOptions(ports: (1...17).map { RunPort(hostPort: 9000 + $0, containerPort: 80) })))
    }

    func testReferenceAndIDValidation() {
        XCTAssertTrue(ImageReference.isValidReference("registry.example.com:5000/team/app:1.2"))
        XCTAssertTrue(ImageReference.isValidReference("app@sha256:abc123"))
        XCTAssertFalse(ImageReference.isValidReference("-v"))
        XCTAssertFalse(ImageReference.isValidReference("a b"))
        XCTAssertFalse(ImageReference.isValidReference("a;rm"))
        XCTAssertTrue(ImageReference.isValidID(String(repeating: "a", count: 64)))
        XCTAssertFalse(ImageReference.isValidID("sha256:" + String(repeating: "a", count: 64)))
        XCTAssertFalse(ImageReference.isValidID("--force"))
    }
}
