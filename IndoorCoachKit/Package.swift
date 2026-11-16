// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "IndoorCoachKit",
    defaultLocalization: "de",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "IndoorCoachKit", targets: ["IndoorCoachKit"])
    ],
    targets: [
        .target(
            name: "IndoorCoachKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "IndoorCoachKitTests",
            dependencies: ["IndoorCoachKit"]
        ),
        // macOS-only helper that renders key screens to PNG for visual review without a simulator.
        .executableTarget(
            name: "SnapshotTool",
            dependencies: ["IndoorCoachKit"]
        )
    ]
)
