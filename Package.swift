// swift-tools-version:5.9
import PackageDescription

// Minimum supported macOS is declared here, explicitly (SMAppService / MenuBar APIs need 13+).
//
// Layout (see docs/architecture.md):
//   MacPeekCore  shared, UI-free services every utility reuses (process inspection, safe termination,
//                permissions, command execution, utility catalog + enable/disable selection)
//   <Name>Kit    one UI-free library per utility (models, parsers, services) — unit-testable anywhere
//   RemoteCrypto    pairing (code + matching words), device identities and the encrypted session for MacPeek Remote
//   RemoteProtocol  the messages a MacPeek Remote console and agent exchange
//   RemoteAgent     serves the Kits to paired consoles; off unless Remote management is switched on
//   MacPeek      the menu-bar app: shell (launcher/router/settings), SharedUI and per-utility views
// Sparkle (the only third-party dependency) powers in-app updates and exists only in the macOS app. It is declared
// only when the manifest is evaluated on macOS so the Linux core-logic CI job never resolves it. The release workflow
// signs updates with the sign_update tool from this same package, so the version here is the only one to maintain.
#if os(macOS)
let sparkleDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
]
let sparkleTargetDependencies: [Target.Dependency] = [.product(name: "Sparkle", package: "Sparkle")]
#else
let sparkleDependencies: [Package.Dependency] = []
let sparkleTargetDependencies: [Target.Dependency] = []
#endif

// RemoteCrypto uses CryptoKit, which exists only on Apple platforms. On Linux (the core-logic CI job) it uses Apple's
// swift-crypto, which has the same API. Like Sparkle, it is declared only for the platform that needs it, so macOS
// builds neither declare nor fetch it.
#if os(Linux)
let cryptoDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/apple/swift-crypto.git", exact: "5.0.3"),
]
let cryptoTargetDependencies: [Target.Dependency] = [.product(name: "Crypto", package: "swift-crypto")]
#else
let cryptoDependencies: [Package.Dependency] = []
let cryptoTargetDependencies: [Target.Dependency] = []
#endif

let package = Package(
    name: "MacPeek",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MacPeek", targets: ["MacPeek"]),
        .library(name: "MacPeekCore", targets: ["MacPeekCore"]),
        .library(name: "PortPeekKit", targets: ["PortPeekKit"]),
        .library(name: "FileLockPeekKit", targets: ["FileLockPeekKit"]),
        .library(name: "DisplayPeekKit", targets: ["DisplayPeekKit"]),
        .library(name: "USBPeekKit", targets: ["USBPeekKit"]),
        .library(name: "SleepPeekKit", targets: ["SleepPeekKit"]),
        .library(name: "ProcessPeekKit", targets: ["ProcessPeekKit"]),
        .library(name: "DiskPeekKit", targets: ["DiskPeekKit"]),
        .library(name: "EnvPeekKit", targets: ["EnvPeekKit"]),
        .library(name: "DNSPeekKit", targets: ["DNSPeekKit"]),
        .library(name: "NetPeekKit", targets: ["NetPeekKit"]),
        .library(name: "SoundPeekKit", targets: ["SoundPeekKit"]),
        .library(name: "UpdatePeekKit", targets: ["UpdatePeekKit"]),
        .library(name: "MemoryPeekKit", targets: ["MemoryPeekKit"]),
        .library(name: "CPUPeekKit", targets: ["CPUPeekKit"]),
        .library(name: "RemoteCrypto", targets: ["RemoteCrypto"]),
        .library(name: "RemoteProtocol", targets: ["RemoteProtocol"]),
        .library(name: "RemoteAgent", targets: ["RemoteAgent"]),
    ],
    dependencies: sparkleDependencies + cryptoDependencies,
    targets: [
        .target(name: "MacPeekCore", path: "Sources/MacPeekCore"),
        .target(name: "PortPeekKit", dependencies: ["MacPeekCore"], path: "Sources/PortPeekKit"),
        .target(name: "FileLockPeekKit", dependencies: ["MacPeekCore"], path: "Sources/FileLockPeekKit"),
        .target(name: "DisplayPeekKit", dependencies: ["MacPeekCore"], path: "Sources/DisplayPeekKit"),
        .target(name: "USBPeekKit", dependencies: ["MacPeekCore"], path: "Sources/USBPeekKit"),
        .target(name: "SleepPeekKit", dependencies: ["MacPeekCore"], path: "Sources/SleepPeekKit"),
        .target(name: "ProcessPeekKit", dependencies: ["MacPeekCore", "PortPeekKit"], path: "Sources/ProcessPeekKit"),
        .target(name: "DiskPeekKit", dependencies: ["MacPeekCore"], path: "Sources/DiskPeekKit"),
        .target(name: "EnvPeekKit", dependencies: ["MacPeekCore"], path: "Sources/EnvPeekKit"),
        .target(name: "DNSPeekKit", dependencies: ["MacPeekCore"], path: "Sources/DNSPeekKit"),
        .target(name: "NetPeekKit", dependencies: ["MacPeekCore", "DNSPeekKit"], path: "Sources/NetPeekKit"),
        .target(name: "SoundPeekKit", dependencies: ["MacPeekCore"], path: "Sources/SoundPeekKit"),
        .target(name: "UpdatePeekKit", dependencies: ["MacPeekCore"], path: "Sources/UpdatePeekKit"),
        .target(name: "MemoryPeekKit", dependencies: ["MacPeekCore"], path: "Sources/MemoryPeekKit"),
        .target(name: "CPUPeekKit", dependencies: ["MacPeekCore"], path: "Sources/CPUPeekKit"),
        .target(name: "RemoteCrypto", dependencies: cryptoTargetDependencies, path: "Sources/RemoteCrypto"),
        .target(name: "RemoteProtocol", dependencies: ["RemoteCrypto", "MacPeekCore", "PortPeekKit", "ProcessPeekKit"],
                path: "Sources/RemoteProtocol"),
        .target(
            name: "RemoteAgent",
            dependencies: ["RemoteCrypto", "RemoteProtocol", "MacPeekCore", "CPUPeekKit", "MemoryPeekKit", "DiskPeekKit",
                           "NetPeekKit", "PortPeekKit", "ProcessPeekKit", "SleepPeekKit", "DNSPeekKit"],
            path: "Sources/RemoteAgent"
        ),
        // SwiftUI/AppKit app. macOS only (files are guarded with #if os(macOS)).
        .executableTarget(
            name: "MacPeek",
            dependencies: ["MacPeekCore", "PortPeekKit", "FileLockPeekKit", "DisplayPeekKit", "USBPeekKit", "SleepPeekKit",
                           "ProcessPeekKit", "DiskPeekKit", "EnvPeekKit", "DNSPeekKit", "NetPeekKit",
                           "SoundPeekKit", "UpdatePeekKit", "MemoryPeekKit", "CPUPeekKit", "RemoteAgent", "RemoteCrypto",
                           "RemoteProtocol"] + sparkleTargetDependencies,
            path: "Sources/MacPeek"
        ),
        .testTarget(name: "MacPeekCoreTests", dependencies: ["MacPeekCore"], path: "Tests/MacPeekCoreTests"),
        .testTarget(
            name: "FileLockPeekKitTests",
            dependencies: ["FileLockPeekKit", "MacPeekCore"],
            path: "Tests/FileLockPeekKitTests",
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "PortPeekKitTests",
            dependencies: ["PortPeekKit", "MacPeekCore"],
            path: "Tests/PortPeekKitTests",
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "DisplayPeekKitTests",
            dependencies: ["DisplayPeekKit", "MacPeekCore"],
            path: "Tests/DisplayPeekKitTests",
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "USBPeekKitTests",
            dependencies: ["USBPeekKit", "MacPeekCore"],
            path: "Tests/USBPeekKitTests",
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "SleepPeekKitTests",
            dependencies: ["SleepPeekKit", "MacPeekCore"],
            path: "Tests/SleepPeekKitTests",
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "ProcessPeekKitTests",
            dependencies: ["ProcessPeekKit", "PortPeekKit", "MacPeekCore"],
            path: "Tests/ProcessPeekKitTests",
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "DiskPeekKitTests", dependencies: ["DiskPeekKit", "MacPeekCore"], path: "Tests/DiskPeekKitTests"),
        .testTarget(name: "MemoryPeekKitTests", dependencies: ["MemoryPeekKit", "MacPeekCore"], path: "Tests/MemoryPeekKitTests"),
        .testTarget(name: "CPUPeekKitTests", dependencies: ["CPUPeekKit", "MacPeekCore"], path: "Tests/CPUPeekKitTests"),
        .testTarget(name: "EnvPeekKitTests", dependencies: ["EnvPeekKit"], path: "Tests/EnvPeekKitTests"),
        .testTarget(
            name: "DNSPeekKitTests",
            dependencies: ["DNSPeekKit", "MacPeekCore"],
            path: "Tests/DNSPeekKitTests",
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "NetPeekKitTests",
            dependencies: ["NetPeekKit", "DNSPeekKit", "MacPeekCore"],
            path: "Tests/NetPeekKitTests",
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "SoundPeekKitTests", dependencies: ["SoundPeekKit", "MacPeekCore"], path: "Tests/SoundPeekKitTests"),
        .testTarget(name: "UpdatePeekKitTests", dependencies: ["UpdatePeekKit", "MacPeekCore"], path: "Tests/UpdatePeekKitTests"),
        .testTarget(name: "RemoteCryptoTests", dependencies: ["RemoteCrypto"], path: "Tests/RemoteCryptoTests"),
        .testTarget(name: "RemoteProtocolTests", dependencies: ["RemoteProtocol", "RemoteCrypto", "MacPeekCore", "PortPeekKit",
                                                       "ProcessPeekKit"], path: "Tests/RemoteProtocolTests"),
        .testTarget(
            name: "RemoteAgentTests",
            dependencies: ["RemoteAgent", "RemoteCrypto", "RemoteProtocol", "MacPeekCore", "CPUPeekKit", "MemoryPeekKit",
                           "DiskPeekKit", "NetPeekKit", "PortPeekKit", "ProcessPeekKit", "SleepPeekKit", "DNSPeekKit"],
            path: "Tests/RemoteAgentTests"
        ),
    ]
)
