import Foundation
import MacPeekCore

/// One row of `docker image ls`: an image under one repository and tag. An image with two tags is two rows with the same
/// `imageID`, because deleting one tag is a different act from deleting the image.
public struct ImageInfo: Identifiable, Equatable, Codable, Sendable {
    public var id: String { "\(imageID)#\(reference ?? "-")" }
    /// The full image ID as 64 hexadecimal characters, without the `sha256:` prefix.
    public let imageID: String
    /// `nil` for an untagged ("dangling") image, which Docker prints as `<none>`.
    public let repository: String?
    public let tag: String?
    /// The engine's own words for the size ("1.24GB"). Layers shared with other images are counted in each of them.
    public let sizeText: String
    public let sizeBytes: UInt64?
    /// "3 weeks ago".
    public let createdSince: String?
    public let createdAt: String?
    /// Names of the containers (running or not) created from this image, as far as their image names can be matched.
    public var usedBy: [String]

    public init(imageID: String, repository: String?, tag: String?, sizeText: String, sizeBytes: UInt64?, createdSince: String?,
                createdAt: String?, usedBy: [String] = []) {
        self.imageID = imageID
        self.repository = repository
        self.tag = tag
        self.sizeText = sizeText
        self.sizeBytes = sizeBytes
        self.createdSince = createdSince
        self.createdAt = createdAt
        self.usedBy = usedBy
    }

    public var shortID: String { String(imageID.prefix(12)) }
    /// `repository:tag`, or nil when the image has no tag (untagged, or known only by digest).
    public var reference: String? {
        guard let repository, let tag else { return nil }
        return "\(repository):\(tag)"
    }
    public var isDangling: Bool { repository == nil }
    public var isInUse: Bool { !usedBy.isEmpty }
    /// What to show as its name.
    public var displayName: String { reference ?? repository ?? "untagged" }
    /// What a command names it by: the tag when there is one (so deleting removes that tag), otherwise the image ID.
    public var target: String { reference ?? imageID }
}

/// The images of the Docker engine on a Mac.
public struct ImageSnapshot: Equatable, Codable, Sendable {
    public let executable: String?
    /// The Docker context in use (Docker Desktop adds `desktop-linux`), when known.
    public let context: String?
    public let status: EngineStatus
    public let images: [ImageInfo]

    public init(executable: String?, context: String?, status: EngineStatus, images: [ImageInfo]) {
        self.executable = executable
        self.context = context
        self.status = status
        self.images = images
    }

    public var inUseCount: Int { images.filter(\.isInUse).count }
}

/// One published port for a new container.
public struct RunPort: Hashable, Codable, Sendable {
    public let hostPort: Int
    public let containerPort: Int
    /// `tcp` or `udp`.
    public let protocolName: String

    public init(hostPort: Int, containerPort: Int, protocolName: String = "tcp") {
        self.hostPort = hostPort
        self.containerPort = containerPort
        self.protocolName = protocolName
    }
}

/// The only choices a person has when starting a container from an image. Everything else is fixed: detached, no pull,
/// no volumes, no environment, no privileges, no command override.
public struct ContainerRunOptions: Equatable, Codable, Sendable {
    public let name: String?
    public let ports: [RunPort]
    /// False (the default) publishes ports on this Mac only (`127.0.0.1`); true publishes them on every interface, so
    /// other devices on the network can reach them.
    public let exposeToNetwork: Bool

    public init(name: String? = nil, ports: [RunPort] = [], exposeToNetwork: Bool = false) {
        self.name = name
        self.ports = ports
        self.exposeToNetwork = exposeToNetwork
    }
}

public enum ContainerRunResult: Equatable, Codable, Sendable {
    /// The container was created and started; `containerID` is its full ID.
    case started(containerID: String)
    /// The image is gone or changed: nothing was done.
    case changed(String)
    case failed(String)

    public var isSuccess: Bool { if case .started = self { return true } else { return false } }

    public func message(image: String) -> String {
        switch self {
        case .started: return "Started a container from \(image)."
        case .changed(let reason): return "Nothing done: \(reason)"
        case .failed(let reason): return "Run failed: \(reason)"
        }
    }
}

public extension ContainerActionResult {
    /// The sentence shown after deleting an image.
    func message(removingImage name: String) -> String {
        switch self {
        case .done: return "Deleted \(name)."
        case .changed(let reason): return "Nothing done: \(reason)"
        case .failed(let reason): return "Delete failed: \(reason)"
        }
    }
}
