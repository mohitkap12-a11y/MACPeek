import Foundation

/// Every utility MacPeek knows about, in launcher order. A utility moves from `.comingSoon` to
/// `.available` in the same change that ships its module.
public enum UtilityCatalog {
    public static let portPeek = UtilityInfo(
        id: "portpeek", name: "PortPeek", question: "What is using port 3000?",
        tagline: "See what's using your ports.",
        summary: "Lists listening TCP and UDP ports with the process behind each one, and frees a port by safely terminating its owner: graceful first, force kill only when you confirm.",
        icon: "network", category: .everyday, availability: .available,
        reads: ["Listening sockets and the processes that own them, for your user account (via lsof)"],
        permissions: ["None to view. You can terminate only processes your user owns."]
    )
    public static let displayPeek = UtilityInfo(
        id: "displaypeek", name: "DisplayPeek", question: "What display configuration am I actually running?",
        tagline: "Know exactly how your displays are configured.",
        summary: "Shows each connected display's real resolution, refresh rate, scaling, HDR state and rotation, with one-click copy.",
        icon: "display", category: .everyday, availability: .comingSoon,
        reads: ["Display modes and properties from macOS display services"],
        permissions: ["None"]
    )
    public static let usbPeek = UtilityInfo(
        id: "usbpeek", name: "USBPeek", question: "What is connected, and at what speed?",
        tagline: "See what's connected to your Mac.",
        summary: "Lists USB and Thunderbolt devices as a tree with vendor, connection type and negotiated link speed. Serial numbers are hidden by default.",
        icon: "cable.connector", category: .everyday, availability: .comingSoon,
        reads: ["USB and Thunderbolt device information from the I/O registry"],
        permissions: ["None"]
    )
    public static let netPeek = UtilityInfo(
        id: "netpeek", name: "NetPeek", question: "Is my network connection actually healthy?",
        tagline: "Understand your network connection.",
        summary: "Shows your active interface, IP addresses, gateway and DNS, plus reachability and latency, and Wi-Fi signal details where macOS allows.",
        icon: "wifi", category: .everyday, availability: .comingSoon,
        reads: ["Network interface configuration; latency to your gateway and DNS only when you run a check"],
        permissions: ["Wi-Fi network name may require Location access on recent macOS versions"]
    )
    public static let batteryPeek = UtilityInfo(
        id: "batterypeek", name: "BatteryPeek", question: "What is my MacBook battery actually doing?",
        tagline: "Understand your MacBook battery.",
        summary: "Shows charge, power source, charging state, cycle count and health indicators that macOS reports, without claiming precision it doesn't have.",
        icon: "battery.100", category: .everyday, availability: .comingSoon,
        reads: ["Battery and power-source information from macOS power services"],
        permissions: ["None"]
    )
    public static let sleepPeek = UtilityInfo(
        id: "sleeppeek", name: "SleepPeek", question: "Why isn't my Mac sleeping?",
        tagline: "Find out why your Mac isn't sleeping.",
        summary: "Read-only diagnostics: active sleep assertions and the processes behind them, plus recent wake times and reasons. Verified facts are kept apart from inference.",
        icon: "moon.zzz", category: .everyday, availability: .comingSoon,
        reads: ["Power-management assertions and the recent sleep/wake log"],
        permissions: ["None"]
    )
    public static let fileLockPeek = UtilityInfo(
        id: "filelockpeek", name: "FileLockPeek", question: "What process is using this file?",
        tagline: "Find what's holding a file open.",
        summary: "Choose a file or folder (or drop one in) and see which of your processes have it open, locked, or as their working directory. Ending a holder is optional and uses the same safe-termination checks as PortPeek; nothing is ever terminated by default.",
        icon: "lock.doc", category: .developer, availability: .available,
        reads: ["Open files of processes owned by your user (via lsof), only for the path you choose, only when you scan"],
        permissions: ["None to scan. Other users' processes are not listed, and you can terminate only processes your user owns."]
    )
    public static let processPeek = UtilityInfo(
        id: "processpeek", name: "ProcessPeek", question: "What exactly is this process?",
        tagline: "Inspect a process and its relationships.",
        summary: "Shows a process's path, parent, user, start time, command line, CPU and memory, listening ports and children. Deliberately not an Activity Monitor replacement.",
        icon: "cpu", category: .developer, availability: .comingSoon,
        reads: ["Process details for processes your user can inspect"],
        permissions: ["None. Some details are unavailable for other users' processes."]
    )
    public static let diskPeek = UtilityInfo(
        id: "diskpeek", name: "DiskPeek", question: "Which app is using my disk right now?",
        tagline: "See which processes are hitting your disk.",
        summary: "Samples per-process disk reads and writes while it is open and clearly labels values as sampled. It stops sampling as soon as you leave it.",
        icon: "internaldrive", category: .developer, availability: .comingSoon,
        reads: ["Per-process disk I/O counters for processes your user can inspect"],
        permissions: ["None. Other users' processes are not shown."]
    )
    public static let envPeek = UtilityInfo(
        id: "envpeek", name: "EnvPeek", question: "What environment variables does this environment see?",
        tagline: "Inspect and search environment variables.",
        summary: "Search variables, inspect PATH and copy NAME=value. Variables are labelled by where they come from, so a per-process value is never presented as global.",
        icon: "terminal", category: .developer, availability: .comingSoon,
        reads: ["MacPeek's own environment and, where permitted, a process's environment"],
        permissions: ["None. Values are shown on screen only and never logged."]
    )
    public static let dnsPeek = UtilityInfo(
        id: "dnspeek", name: "DNSPeek", question: "Which DNS servers is my Mac using, and do they respond?",
        tagline: "Inspect DNS configuration and resolver behavior.",
        summary: "Read-only view of the active interface, resolver configuration and DNS servers, with lookup latency measured on request. It never changes DNS settings.",
        icon: "server.rack", category: .developer, availability: .comingSoon,
        reads: ["System resolver configuration; lookups only when you run a check"],
        permissions: ["None"]
    )

    public static let all: [UtilityInfo] = [
        portPeek, displayPeek, usbPeek, netPeek, batteryPeek, sleepPeek,
        fileLockPeek, processPeek, diskPeek, envPeek, dnsPeek,
    ]

    public static func info(for id: String) -> UtilityInfo? { all.first { $0.id == id } }
}
