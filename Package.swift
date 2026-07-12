// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Unison",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CIOAVService", path: "Sources/CIOAVService"),
        .executableTarget(
            name: "Unison",
            dependencies: ["CIOAVService"],
            path: "Sources/Unison",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        ),
        // Run tests via Scripts/test.sh: swift-testing ships with the Command
        // Line Tools off the default search path and needs extra flags.
        .testTarget(name: "UnisonTests", dependencies: ["Unison"], path: "Tests/UnisonTests")
    ]
)
