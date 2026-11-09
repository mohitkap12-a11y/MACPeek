import Foundation
import MacPeekCore

/// Parses `docker ps -a --no-trunc --format '{{json .}}'` (one JSON object per line).
public enum DockerPSParser {
    public static func parse(_ text: String) -> [ContainerInfo] {
        LooseJSON.objects(text).compactMap { object in
            guard let id = LooseJSON.text(object, "ID") else { return nil }
            let status = LooseJSON.text(object, "Status") ?? ""
            let state = LooseJSON.text(object, "State").map(ContainerState.init(raw:)) ?? ContainerState(status: status)
            let labels = LabelParser.parse(LooseJSON.string(object, "Labels") ?? "")
            let names = (LooseJSON.text(object, "Names") ?? id).split(separator: ",").map(String.init)
            return ContainerInfo(
                id: id, name: names.first ?? id, image: LooseJSON.text(object, "Image") ?? "",
                state: state, status: status, ports: DockerPortsParser.parse(LooseJSON.string(object, "Ports") ?? ""),
                composeProject: labels["com.docker.compose.project"], composeService: labels["com.docker.compose.service"],
                createdAt: LooseJSON.text(object, "CreatedAt"))
        }
    }
}

/// `com.docker.compose.project=web,com.docker.compose.service=db` → a dictionary. Values containing commas are rare
/// and only the Compose labels are used, so a simple split is enough.
public enum LabelParser {
    public static func parse(_ text: String) -> [String: String] {
        var labels: [String: String] = [:]
        for pair in text.split(separator: ",") {
            guard let equals = pair.firstIndex(of: "=") else { continue }
            let key = pair[..<equals].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { labels[key] = String(pair[pair.index(after: equals)...]) }
        }
        return labels
    }
}

/// Docker's port column: `0.0.0.0:8080->80/tcp, :::8080->80/tcp, 5432/tcp, 127.0.0.1:9000-9001->9000-9001/tcp`.
/// The same mapping printed once for IPv4 and once for IPv6 is kept once (as the IPv4 wildcard).
public enum DockerPortsParser {
    private static let published = NSRegularExpression.compile(#"^(.*):(\d+)(?:-(\d+))?->(\d+)(?:-(\d+))?/(\w+)$"#)
    private static let exposed = NSRegularExpression.compile(#"^(\d+)(?:-(\d+))?/(\w+)$"#)

    public static func parse(_ text: String) -> [PortMapping] {
        var result: [PortMapping] = []
        for raw in text.split(separator: ",") {
            let item = raw.trimmingCharacters(in: .whitespaces)
            if let g = published.groups(in: item), let host = g[2].flatMap(Int.init), let inside = g[4].flatMap(Int.init), let proto = g[6] {
                var ip = g[1] ?? ""
                if ip.hasPrefix("[") && ip.hasSuffix("]") { ip = String(ip.dropFirst().dropLast()) }
                let mapping = PortMapping(hostIP: ip.isEmpty ? nil : ip, hostPort: host, containerPort: inside,
                                          containerPortEnd: g[5].flatMap(Int.init), protocolName: proto)
                let isWildcard6 = ip == "::" || ip.isEmpty
                if isWildcard6, result.contains(where: { $0.hostPort == host && $0.containerPort == inside && $0.protocolName == proto }) {
                    continue
                }
                result.append(mapping)
            } else if let g = exposed.groups(in: item), let inside = g[1].flatMap(Int.init), let proto = g[3] {
                result.append(PortMapping(hostIP: nil, hostPort: nil, containerPort: inside, containerPortEnd: g[2].flatMap(Int.init),
                                          protocolName: proto))
            }
        }
        return result
    }
}

/// Parses `docker stats --no-stream --no-trunc --format '{{json .}}'`, keyed by container ID.
public enum DockerStatsParser {
    public static func parse(_ text: String) -> [String: ContainerStats] {
        var result: [String: ContainerStats] = [:]
        for object in LooseJSON.objects(text) {
            guard let id = LooseJSON.text(object, "ID") ?? LooseJSON.text(object, "Container") else { continue }
            result[id] = stats(cpu: LooseJSON.string(object, "CPUPerc"), memory: LooseJSON.string(object, "MemUsage"),
                               memoryPercent: LooseJSON.string(object, "MemPerc"), pids: LooseJSON.string(object, "PIDs"))
        }
        return result
    }

    static func stats(cpu: String?, memory: String?, memoryPercent: String?, pids: String?) -> ContainerStats {
        let parts = (memory ?? "").components(separatedBy: "/")
        return ContainerStats(
            cpuPercent: cpu.flatMap(ByteSizeText.percent),
            memoryUsedBytes: parts.first.flatMap(ByteSizeText.parse),
            memoryLimitBytes: parts.count > 1 ? ByteSizeText.parse(parts[1]) : nil,
            memoryPercent: memoryPercent.flatMap(ByteSizeText.percent),
            pids: pids.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) })
    }
}

/// Parses `podman ps -a --format json` (a JSON array whose field names differ from Docker's).
public enum PodmanPSParser {
    public static func parse(_ text: String) -> [ContainerInfo] {
        LooseJSON.objects(text).compactMap { object in
            guard let id = LooseJSON.text(object, "Id") ?? LooseJSON.text(object, "ID") else { return nil }
            let names = LooseJSON.strings(object, "Names")
            let status = LooseJSON.text(object, "Status") ?? ""
            let state = LooseJSON.text(object, "State").map(ContainerState.init(raw:)) ?? ContainerState(status: status)
            let labels = (object["Labels"] as? [String: Any])?.compactMapValues { $0 as? String } ?? [:]
            let ports: [PortMapping] = LooseJSON.array(object, "Ports").compactMap { port in
                guard let inside = LooseJSON.int(port, "container_port") else { return nil }
                let range = LooseJSON.int(port, "range") ?? 1
                let host = LooseJSON.int(port, "host_port")
                return PortMapping(hostIP: LooseJSON.text(port, "host_ip"), hostPort: host == 0 ? nil : host, containerPort: inside,
                                   containerPortEnd: range > 1 ? inside + range - 1 : nil,
                                   protocolName: LooseJSON.text(port, "protocol") ?? "tcp")
            }
            let createdAt = LooseJSON.text(object, "CreatedAt")
            return ContainerInfo(id: id, name: names.first ?? String(id.prefix(12)), image: LooseJSON.text(object, "Image") ?? "",
                                 state: state, status: status.isEmpty ? state.label : status, ports: ports,
                                 composeProject: labels["com.docker.compose.project"] ?? labels["io.podman.compose.project"],
                                 composeService: labels["com.docker.compose.service"], createdAt: createdAt)
        }
    }
}

/// Parses `podman stats --no-stream --format json`, keyed by the (short) ID Podman prints.
public enum PodmanStatsParser {
    public static func parse(_ text: String) -> [String: ContainerStats] {
        var result: [String: ContainerStats] = [:]
        for object in LooseJSON.objects(text) {
            guard let id = LooseJSON.text(object, "id") ?? LooseJSON.text(object, "ID") else { continue }
            result[id] = DockerStatsParser.stats(cpu: LooseJSON.string(object, "cpu_percent") ?? LooseJSON.string(object, "CPU"),
                                                 memory: LooseJSON.string(object, "mem_usage") ?? LooseJSON.string(object, "MemUsage"),
                                                 memoryPercent: LooseJSON.string(object, "mem_percent") ?? LooseJSON.string(object, "Mem"),
                                                 pids: LooseJSON.string(object, "pids") ?? LooseJSON.string(object, "PIDS"))
        }
        return result
    }
}

/// Attaches stats to containers. Docker keys stats by the full ID; Podman by a 12-character prefix.
public enum ContainerStatsMerge {
    public static func merge(_ containers: [ContainerInfo], stats: [String: ContainerStats]) -> [ContainerInfo] {
        containers.map { container in
            var copy = container
            copy.stats = stats[container.id] ?? stats.first { !$0.key.isEmpty && container.id.hasPrefix($0.key) }?.value
            return copy
        }
    }
}

/// Virtual machine lists from the managers MacPeek knows.
public enum VMListParser {
    /// `limactl list --json`: one object per line.
    public static func lima(_ text: String) -> [VirtualMachine] {
        LooseJSON.objects(text).compactMap { object in
            guard let name = LooseJSON.text(object, "name") else { return nil }
            let status = LooseJSON.text(object, "status") ?? "Unknown"
            let detail = [LooseJSON.text(object, "vmType"), LooseJSON.text(object, "arch")].compactMap { $0 }.joined(separator: " · ")
            return VirtualMachine(source: .lima, name: name, state: status, isRunning: status.lowercased() == "running",
                                  cpus: LooseJSON.int(object, "cpus"), memoryBytes: LooseJSON.uint64(object, "memory"),
                                  diskBytes: LooseJSON.uint64(object, "disk"), detail: detail.isEmpty ? nil : detail)
        }
    }

    /// `colima list --json`: one object per line.
    public static func colima(_ text: String) -> [VirtualMachine] {
        LooseJSON.objects(text).compactMap { object in
            guard let name = LooseJSON.text(object, "name") else { return nil }
            let status = LooseJSON.text(object, "status") ?? "Unknown"
            let detail = [LooseJSON.text(object, "runtime"), LooseJSON.text(object, "arch")].compactMap { $0 }.joined(separator: " · ")
            return VirtualMachine(source: .colima, name: name, state: status, isRunning: status.lowercased() == "running",
                                  cpus: LooseJSON.int(object, "cpus"), memoryBytes: LooseJSON.uint64(object, "memory"),
                                  diskBytes: LooseJSON.uint64(object, "disk"), detail: detail.isEmpty ? nil : detail)
        }
    }

    /// `tart list --format json`: an array; `Disk` and `Size` are in GB.
    public static func tart(_ text: String) -> [VirtualMachine] {
        LooseJSON.objects(text).compactMap { object in
            guard let name = LooseJSON.text(object, "Name") else { return nil }
            let running = LooseJSON.bool(object, "Running") ?? (LooseJSON.text(object, "State")?.lowercased() == "running")
            let state = LooseJSON.text(object, "State") ?? (running ? "running" : "stopped")
            let disk = LooseJSON.double(object, "Disk").map { UInt64($0 * 1_000_000_000) }
            return VirtualMachine(source: .tart, name: name, state: state, isRunning: running, cpus: nil, memoryBytes: nil,
                                  diskBytes: disk, detail: LooseJSON.text(object, "Source"))
        }
    }

    /// `prlctl list --all --json`: an array.
    public static func parallels(_ text: String) -> [VirtualMachine] {
        LooseJSON.objects(text).compactMap { object in
            guard let name = LooseJSON.text(object, "name") else { return nil }
            let status = LooseJSON.text(object, "status") ?? "unknown"
            return VirtualMachine(source: .parallels, name: name, state: status, isRunning: status.lowercased() == "running",
                                  cpus: nil, memoryBytes: nil, diskBytes: nil, detail: nil)
        }
    }
}

/// Which processes host a virtual machine, by the name macOS reports for them (`proc_name`, at most 32 characters).
public enum VMHostProcessMatcher {
    public static func kind(of name: String) -> String? {
        let lower = name.lowercased()
        if lower.hasPrefix("com.apple.virtualization") { return "Apple Virtualization VM" }
        if lower.hasPrefix("qemu-system") { return "QEMU VM" }
        if lower == "prl_vm_app" || lower.hasPrefix("prl_vm") { return "Parallels VM" }
        if lower == "vmware-vmx" { return "VMware Fusion VM" }
        if lower.hasPrefix("com.docker.virtualization") || lower == "com.docker.krun" || lower == "com.docker.hyperkit" {
            return "Docker Desktop VM"
        }
        if lower == "krunkit" || lower == "vfkit" { return "Podman machine VM" }
        if lower == "orbstack helper" || lower == "orbstack-helper" { return "OrbStack VM" }
        return nil
    }
}

/// The ID rule every engine follows. Only IDs that match are ever put on a command line, so a value from the console
/// or from another tool's output can never become an option.
public enum ContainerID {
    private static let pattern = NSRegularExpression.compile(#"^[0-9a-f]{12,64}$"#)
    public static func isValid(_ id: String) -> Bool { pattern.groups(in: id) != nil }
}
