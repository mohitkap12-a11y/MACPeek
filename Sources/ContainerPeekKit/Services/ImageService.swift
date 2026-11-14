import Foundation
import MacPeekCore

public protocol ImageReading: Sendable {
    /// The Docker engine's images, each with the containers made from it.
    func snapshot() async throws -> ImageSnapshot
}

public protocol ImageControlling: Sendable {
    /// Re-reads the image, checks it is still the one the person saw, then deletes it (or just the tag they chose).
    func remove(_ image: ImageInfo) async -> ContainerActionResult
    /// Re-reads the image, checks it is still the one the person saw, then starts a container from it.
    func run(_ image: ImageInfo, options: ContainerRunOptions) async -> ContainerRunResult
}

/// Lists images with `docker image ls` and the containers with `docker ps` (fixed argument lists, never a shell). Docker
/// only: images are not read for Podman.
public struct SystemImageReader: ImageReading {
    private let runner: CommandRunning
    private let tools: ContainerToolLocators

    public init(runner: CommandRunning = ShellCommand(timeout: 20), tools: ContainerToolLocators = .standard) {
        self.runner = runner
        self.tools = tools
    }

    public func snapshot() async throws -> ImageSnapshot {
        guard let path = tools.docker.locate() else {
            return ImageSnapshot(executable: nil, context: nil,
                                 status: .failed("Docker is not installed in a location MacPeek checks."), images: [])
        }
        var context: String?
        if let output = try await attempt(path, ["context", "show"]), output.status == 0 {
            context = SystemContainerReader.firstLine(output.stdout)
        }
        guard let list = try await attempt(path, SystemImageController.listArguments) else {
            return ImageSnapshot(executable: path, context: context, status: .failed("Docker did not answer in time."), images: [])
        }
        guard list.status == 0 else {
            return ImageSnapshot(executable: path, context: context, status: SystemContainerReader.failureStatus(.docker, list), images: [])
        }
        var images = DockerImagesParser.parse(list.stdout)
        // Which images are in use is a convenience: if the container list cannot be read, the images are still listed.
        if let ps = try await attempt(path, ["ps", "--all", "--no-trunc", "--format", "{{json .}}"]), ps.status == 0 {
            images = ImageUsage.apply(to: images, containers: DockerPSParser.parse(ps.stdout))
        }
        images.sort { ($0.isDangling ? 1 : 0, $0.displayName, $0.imageID) < ($1.isDangling ? 1 : 0, $1.displayName, $1.imageID) }
        return ImageSnapshot(executable: path, context: context, status: .running, images: images)
    }

    private func attempt(_ executable: String, _ arguments: [String]) async throws -> CommandOutput? {
        do { return try await runner.run(executable, arguments) }
        catch is CancellationError { throw CancellationError() }
        catch CommandError.cancelled { throw CommandError.cancelled }
        catch { return nil }
    }
}

/// Deletes images and starts containers through the Docker CLI. Each action is one fixed command:
///
/// - `docker image rm <repo:tag | image id>`: never `--force`, never `--no-prune`. Docker itself refuses an image a
///   container still uses, and that refusal is shown as it is.
/// - `docker run -d --pull never [--name N] [-p …] <repo:tag | image id>`: detached, never pulls, and nothing else: no
///   volumes, environment, privileges, host networking or command override. Ports bind to `127.0.0.1` unless the person
///   chose to expose them to the network.
///
/// Before acting it lists the images again and refuses if the one the person saw is gone or is now a different image.
public struct SystemImageController: ImageControlling {
    static let listArguments = ["image", "ls", "--no-trunc", "--format", "{{json .}}"]

    private let runner: CommandRunning
    private let tools: ContainerToolLocators

    public init(runner: CommandRunning = ShellCommand(timeout: 60), tools: ContainerToolLocators = .standard) {
        self.runner = runner
        self.tools = tools
    }

    public func remove(_ image: ImageInfo) async -> ContainerActionResult {
        if let problem = Self.problem(with: image) { return .failed(problem) }
        guard let path = tools.docker.locate() else { return .failed("Docker is not installed.") }
        do {
            let current: ImageInfo
            switch try await find(image, path: path) {
            case .found(let found): current = found
            case .gone(let reason): return .changed(reason)
            }
            let output = try await runner.run(path, ["image", "rm", current.target])
            guard output.status == 0 else {
                return .failed(SystemContainerReader.firstLine(output.stderr) ?? "Docker exited with status \(output.status)")
            }
            return .done
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    public func run(_ image: ImageInfo, options: ContainerRunOptions) async -> ContainerRunResult {
        if let problem = Self.problem(with: image) ?? ImageReference.problem(with: options) { return .failed(problem) }
        guard let path = tools.docker.locate() else { return .failed("Docker is not installed.") }
        do {
            let current: ImageInfo
            switch try await find(image, path: path) {
            case .found(let found): current = found
            case .gone(let reason): return .changed(reason)
            }
            let output = try await runner.run(path, Self.runArguments(image: current, options: options))
            guard output.status == 0 else {
                return .failed(SystemContainerReader.firstLine(output.stderr) ?? "Docker exited with status \(output.status)")
            }
            guard let id = SystemContainerReader.firstLine(output.stdout), ContainerID.isValid(id) else {
                return .failed("Docker started the container but did not report its ID.")
            }
            return .started(containerID: id)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// The exact argument list for `docker run`. Public so tests (and the docs) can state precisely what is run.
    public static func runArguments(image: ImageInfo, options: ContainerRunOptions) -> [String] {
        var arguments = ["run", "--detach", "--pull", "never"]
        if let name = options.name, !name.isEmpty { arguments += ["--name", name] }
        for port in options.ports {
            let bind = options.exposeToNetwork ? "" : "127.0.0.1:"
            arguments += ["--publish", "\(bind)\(port.hostPort):\(port.containerPort)/\(port.protocolName)"]
        }
        arguments.append(image.target)
        return arguments
    }

    public static func problem(with image: ImageInfo) -> String? {
        guard ImageReference.isValidID(image.imageID) else { return "That is not an image ID." }
        if let reference = image.reference, !ImageReference.isValidReference(reference) { return "That is not an image name." }
        return nil
    }

    private enum Lookup { case found(ImageInfo), gone(String) }

    private func find(_ image: ImageInfo, path: String) async throws -> Lookup {
        let list = try await runner.run(path, Self.listArguments)
        guard list.status == 0 else {
            throw ContainerError.commandFailed(SystemContainerReader.firstLine(list.stderr) ?? "Docker could not list images.")
        }
        let found = DockerImagesParser.parse(list.stdout).first { $0.imageID == image.imageID && $0.reference == image.reference }
        guard let found else { return .gone("\(image.displayName) no longer exists, or is now a different image.") }
        return .found(found)
    }
}
