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
        .testTarget(name: "UnisonTests", dependencies: ["Unison"], path: "Tests/UnisonTests")
    ]
)
