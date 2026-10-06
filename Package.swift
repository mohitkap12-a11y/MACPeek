// swift-tools-version:5.9
import PackageDescription

// Minimum supported macOS is declared here, explicitly (SMAppService / MenuBar APIs need 13+).
let package = Package(
    name: "PortPeek",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PortPeek", targets: ["PortPeek"]),
        .library(name: "PortPeekCore", targets: ["PortPeekCore"]),
    ],
    targets: [
        // Pure Foundation logic: discovery, parsing, search, safe termination.
        // Builds and tests on any platform with a Swift toolchain.
        .target(name: "PortPeekCore", path: "Sources/PortPeekCore"),
        // SwiftUI/AppKit menu-bar app. macOS only (files are guarded with #if os(macOS)).
        .executableTarget(name: "PortPeek", dependencies: ["PortPeekCore"], path: "Sources/PortPeek"),
        .testTarget(
            name: "PortPeekCoreTests",
            dependencies: ["PortPeekCore"],
            path: "Tests/PortPeekCoreTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
