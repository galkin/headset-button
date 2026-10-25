// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HeadsetButton",
    platforms: [.macOS(.v15)],
    targets: [
        // Pure logic: no AppKit, SwiftUI or MediaPlayer. Covered by HeadsetButtonCoreTests.
        .target(name: "HeadsetButtonCore"),
        // The app: AppKit / SwiftUI / MediaPlayer glue around HeadsetButtonCore.
        .executableTarget(
            name: "HeadsetButton",
            dependencies: ["HeadsetButtonCore"]
        ),
        .testTarget(
            name: "HeadsetButtonCoreTests",
            dependencies: ["HeadsetButtonCore"]
        ),
    ]
)
