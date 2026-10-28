// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ServiceDock",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "ServiceDock", targets: ["ServiceDock"])
    ],
    targets: [
        // Pure value-type logic: models, log parsing, stats parsing. Fully unit tested.
        .target(name: "ServiceDockCore"),
        // The menu-bar app: process spawning, runtime state, SwiftUI views.
        .executableTarget(
            name: "ServiceDock",
            dependencies: ["ServiceDockCore"]
        ),
        .testTarget(name: "ServiceDockCoreTests", dependencies: ["ServiceDockCore"])
    ]
)
