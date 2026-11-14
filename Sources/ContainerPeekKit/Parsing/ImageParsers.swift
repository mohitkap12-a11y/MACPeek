import Foundation
import MacPeekCore

/// Parses `docker image ls --no-trunc --format '{{json .}}'` (one JSON object per line).
public enum DockerImagesParser {
    public static func parse(_ text: String) -> [ImageInfo] {
        LooseJSON.objects(text).compactMap { object in
            guard let raw = LooseJSON.text(object, "ID") else { return nil }
            let id = raw.hasPrefix("sha256:") ? String(raw.dropFirst("sha256:".count)) : raw
            guard !id.isEmpty else { return nil }
            let size = LooseJSON.text(object, "Size") ?? ""
            return ImageInfo(imageID: id, repository: named(LooseJSON.text(object, "Repository")), tag: named(LooseJSON.text(object, "Tag")),
                             sizeText: size, sizeBytes: ByteSizeText.parse(size), createdSince: LooseJSON.text(object, "CreatedSince"),
                             createdAt: LooseJSON.text(object, "CreatedAt"))
        }
    }

    /// Docker prints `<none>` for a missing repository or tag.
    private static func named(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value != "<none>" else { return nil }
        return value
    }
}

/// Matches containers to the images they were created from, from the image name each container shows.
public enum ImageUsage {
    public static func apply(to images: [ImageInfo], containers: [ContainerInfo]) -> [ImageInfo] {
        images.map { image in
            var copy = image
            copy.usedBy = containers.filter { uses($0.image, image) }.map(\.name)
            return copy
        }
    }

    /// A container's image is shown as it was given: `nginx:1.25`, `nginx` (meaning `nginx:latest`), or an ID prefix.
    static func uses(_ name: String, _ image: ImageInfo) -> Bool {
        if let reference = image.reference {
            if name == reference { return true }
            if image.tag == "latest", name == image.repository { return true }
        }
        let bare = name.hasPrefix("sha256:") ? String(name.dropFirst("sha256:".count)) : name
        return ImageReference.isValidID(bare) && image.imageID.hasPrefix(bare)
    }
}

/// What may be passed to the engine as an image or an option value. Anything else is refused before a command is built.
public enum ImageReference {
    private static let identifier = NSRegularExpression.compile(#"^[0-9a-f]{12,64}$"#)
    /// `registry:5000/team/app:1.2`, `app@sha256:…`. It cannot start with `-`, so it can never be read as an option.
    private static let reference = NSRegularExpression.compile(#"^[A-Za-z0-9][A-Za-z0-9._/:@-]{0,254}$"#)
    private static let containerName = NSRegularExpression.compile(#"^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$"#)

    public static func isValidID(_ id: String) -> Bool { identifier.groups(in: id) != nil }
    public static func isValidReference(_ value: String) -> Bool { reference.groups(in: value) != nil }
    public static func isValidContainerName(_ value: String) -> Bool { containerName.groups(in: value) != nil }

    /// The reason these options cannot be used, or nil when they are fine.
    public static func problem(with options: ContainerRunOptions) -> String? {
        if let name = options.name, !isValidContainerName(name) {
            return "A container name may use letters, digits, underscores, dots and hyphens, and must start with a letter or digit."
        }
        if options.ports.count > 16 { return "At most 16 ports can be published." }
        var seen = Set<String>()
        for port in options.ports {
            guard (1...65535).contains(port.hostPort), (1...65535).contains(port.containerPort) else {
                return "Ports must be between 1 and 65535."
            }
            guard port.protocolName == "tcp" || port.protocolName == "udp" else { return "A port must be tcp or udp." }
            if !seen.insert("\(port.hostPort)/\(port.protocolName)").inserted {
                return "Port \(port.hostPort)/\(port.protocolName) is listed twice."
            }
        }
        return nil
    }
}
