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
        summary: "Shows each connected display's panel resolution, \"looks like\" resolution, refresh rate and scaling, plus anything else macOS reports about it, with one-click copy. Details macOS does not report are left out, never guessed.",
        icon: "display", category: .everyday, availability: .available,
        reads: ["Display properties from macOS (via system_profiler), only while DisplayPeek is open"],
        permissions: ["None"]
    )
    public static let usbPeek = UtilityInfo(
        id: "usbpeek", name: "USBPeek", question: "What is connected, and at what speed?",
        tagline: "See what's connected to your Mac.",
        summary: "Lists connected USB devices as a tree with vendor and the link speed macOS reports, plus the status of your Thunderbolt / USB4 ports. Serial numbers are never read.",
        icon: "cable.connector", category: .everyday, availability: .available,
        reads: ["USB devices from the I/O registry (ioreg) and Thunderbolt port status (system_profiler), only while USBPeek is open"],
        permissions: ["None"]
    )
    public static let netPeek = UtilityInfo(
        id: "netpeek", name: "NetPeek", question: "Is my network connection actually healthy?",
        tagline: "Understand your network connection.",
        summary: "Shows your active interface, IP addresses, router and DNS servers, Wi-Fi signal details where macOS allows, and, only when you press Run checks, whether your router and DNS servers answer pings. Measured facts are kept apart from inference.",
        icon: "wifi", category: .everyday, availability: .available,
        reads: ["Network configuration (route, scutil, networksetup) and Wi-Fi details (system_profiler) while NetPeek is open; pings to your router and DNS servers only when you press Run checks"],
        permissions: ["None. macOS hides the Wi-Fi network name from apps without Location access, and MacPeek does not request it."]
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
        icon: "moon.zzz", category: .everyday, availability: .available,
        reads: ["Power-management assertions and settings (pmset); the sleep/wake log only when you ask for it"],
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
        summary: "Shows how a process was launched, its parent, user, start time, command line, CPU and memory, the listening ports of your own processes, and its children. Ending a process is optional and uses the same safe-termination checks as PortPeek. Deliberately not an Activity Monitor replacement.",
        icon: "cpu", category: .developer, availability: .available,
        reads: ["The process list (ps); a process's command line and listening ports only when you open it"],
        permissions: ["None to inspect. Some details are unavailable for other users' processes, and you can terminate only processes your user owns."]
    )
    public static let diskPeek = UtilityInfo(
        id: "diskpeek", name: "DiskPeek", question: "Which app is using my disk right now?",
        tagline: "See which processes are hitting your disk.",
        summary: "Samples per-process disk reads and writes while it is open and clearly labels values as sampled. It stops sampling as soon as you leave it.",
        icon: "internaldrive", category: .developer, availability: .available,
        reads: ["Per-process disk I/O counters (libproc) for processes your user can inspect, only while DiskPeek is open"],
        permissions: ["None. Other users' processes are not shown."]
    )
    public static let envPeek = UtilityInfo(
        id: "envpeek", name: "EnvPeek", question: "What environment variables does this environment see?",
        tagline: "Inspect and search environment variables.",
        summary: "Search variables, inspect PATH and copy NAME=value. Variables are labelled by where they come from, so a per-process value is never presented as global.",
        icon: "terminal", category: .developer, availability: .available,
        reads: ["MacPeek's own environment and, where macOS permits, the environment of one process whose PID you enter"],
        permissions: ["None. Values are shown on screen only and never logged."]
    )
    public static let dnsPeek = UtilityInfo(
        id: "dnspeek", name: "DNSPeek", question: "Which DNS servers is my Mac using, and do they respond?",
        tagline: "Inspect DNS configuration and resolver behavior.",
        summary: "Read-only view of the active interface, resolver configuration and DNS servers, with lookup latency measured on request. It never changes DNS settings.",
        icon: "server.rack", category: .developer, availability: .available,
        reads: ["The system resolver configuration (scutil --dns); DNS lookups only when you press Run lookup"],
        permissions: ["None"]
    )

    public static let soundPeek = UtilityInfo(
        id: "soundpeek", name: "SoundPeek", question: "Why is my audio going to the wrong place?",
        tagline: "See your audio devices and which are active.",
        summary: "Lists your audio input and output devices with the current defaults, connection type, sample rate, channels and the volume and mute state a device exposes. You can pick a default device or mute one when the device allows it, and undo a change. It never records or listens to audio, and values a device doesn't report are shown as unavailable.",
        icon: "speaker.wave.2", category: .everyday, availability: .available,
        reads: ["Audio device properties from Core Audio (names, connection, formats, volume and mute); device changes while SoundPeek is open"],
        permissions: ["None. SoundPeek never opens an audio stream, so macOS never asks for Microphone access."]
    )
    public static let startupPeek = UtilityInfo(
        id: "startuppeek", name: "StartupPeek", question: "What starts automatically on this Mac?",
        tagline: "See what launches at login or runs in the background.",
        summary: "A read-only inventory of launch agents and daemons you can read, plus MacPeek's own login item, each labelled with where it was found, what kind it is and what it appears to belong to. It cannot list the apps shown in System Settings' Login Items list, says so, and never disables, removes or edits anything.",
        icon: "power", category: .everyday, availability: .available,
        reads: ["Launch agent and daemon property lists in ~/Library/LaunchAgents, /Library/LaunchAgents and /Library/LaunchDaemons; code-signature team IDs of the programs they name"],
        permissions: ["None. Items macOS or the file system keeps private are listed as not visible, not worked around."]
    )
    public static let updatePeek = UtilityInfo(
        id: "updatepeek", name: "UpdatePeek", question: "What updates can MacPeek verify?",
        tagline: "See your macOS version and outdated Homebrew packages.",
        summary: "Shows your macOS version and build, opens Software Update, and, when Homebrew is installed and you press Check, lists the packages Homebrew reports as outdated. It does not check for macOS or other app updates, never installs anything, and never claims your Mac is up to date.",
        icon: "arrow.triangle.2.circlepath", category: .everyday, availability: .available,
        reads: ["The macOS version and build; `brew outdated` (read-only, no brew update) only when Homebrew is installed and you press Check"],
        permissions: ["None. Updates are never installed from MacPeek."]
    )
    public static let privacyPeek = UtilityInfo(
        id: "privacypeek", name: "PrivacyPeek", question: "What does this macOS privacy permission mean?",
        tagline: "Learn what each privacy permission means.",
        summary: "A plain-language guide to macOS privacy permissions with a button to open each pane in System Settings. Informational only: it does not read which apps hold a permission and cannot grant, revoke or reset one.",
        icon: "hand.raised", category: .everyday, availability: .available,
        reads: ["Nothing from your Mac. The guide is built into MacPeek."],
        permissions: ["None. It never requests, reads or changes any permission."]
    )

    public static let all: [UtilityInfo] = [
        portPeek, displayPeek, usbPeek, netPeek, batteryPeek, sleepPeek,
        fileLockPeek, processPeek, diskPeek, envPeek, dnsPeek,
        soundPeek, startupPeek, updatePeek, privacyPeek,
    ]

    public static func info(for id: String) -> UtilityInfo? { all.first { $0.id == id } }
}
