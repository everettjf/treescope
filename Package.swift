// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Treescope",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
    ],
    products: [
        // Shared wire/data model. Pure Foundation, every platform.
        .library(name: "TreescopeProtocol", targets: ["TreescopeProtocol"]),
        // Debug-only runtime injected into the app being inspected. Serves the
        // browser viewer over loopback HTTP + WebSocket.
        .library(name: "TreescopeServer", targets: ["TreescopeServer"]),
        // A sample app that embeds the server, used for end-to-end testing.
        .executable(name: "TreescopeDemo", targets: ["TreescopeDemo"]),
    ],
    targets: [
        .target(
            name: "TreescopeProtocol"
        ),
        .target(
            name: "TreescopeServer",
            dependencies: ["TreescopeProtocol"],
            resources: [.copy("Resources/viewer.html")]
        ),
        .executableTarget(
            name: "TreescopeDemo",
            dependencies: ["TreescopeServer", "TreescopeProtocol"]
        ),
        .testTarget(
            name: "TreescopeProtocolTests",
            dependencies: ["TreescopeProtocol"]
        ),
        .testTarget(
            name: "TreescopeServerTests",
            dependencies: ["TreescopeServer", "TreescopeProtocol"]
        ),
    ]
)
