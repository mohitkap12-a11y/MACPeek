// swift-tools-version:5.9
import PackageDescription

// Minimum supported macOS is declared here, explicitly (SMAppService / MenuBar APIs need 13+).
//
// Layout (see docs/architecture.md):
//   MacPeekCore  shared, UI-free services every utility reuses (process inspection, safe termination,
//                permissions, command execution, utility catalog + enable/disable selection)
//   <Name>Kit    one UI-free library per utility (models, parsers, services) — unit-testable anywhere
//   MacPeek      the menu-bar app: shell (launcher/router/settings), SharedUI and per-utility views
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
    ],
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
        // SwiftUI/AppKit app. macOS only (files are guarded with #if os(macOS)).
        .executableTarget(
            name: "MacPeek",
            dependencies: ["MacPeekCore", "PortPeekKit", "FileLockPeekKit", "DisplayPeekKit", "USBPeekKit", "SleepPeekKit",
                           "ProcessPeekKit", "DiskPeekKit", "EnvPeekKit", "DNSPeekKit", "NetPeekKit",
                           "SoundPeekKit", "UpdatePeekKit"],
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
        .testTarget(name: "DiskPeekKitTests", dependencies: ["DiskPeekKit"], path: "Tests/DiskPeekKitTests"),
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
    ]
)
