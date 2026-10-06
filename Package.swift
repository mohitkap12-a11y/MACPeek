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
    ],
    targets: [
        .target(name: "MacPeekCore", path: "Sources/MacPeekCore"),
        .target(name: "PortPeekKit", dependencies: ["MacPeekCore"], path: "Sources/PortPeekKit"),
        .target(name: "FileLockPeekKit", dependencies: ["MacPeekCore"], path: "Sources/FileLockPeekKit"),
        // SwiftUI/AppKit app. macOS only (files are guarded with #if os(macOS)).
        .executableTarget(
            name: "MacPeek",
            dependencies: ["MacPeekCore", "PortPeekKit", "FileLockPeekKit"],
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
    ]
)
