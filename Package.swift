// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AirPodsMouse",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AirPodsMouse",
            path: "Sources/AirPodsMouse",
            linkerSettings: [
                .linkedFramework("CoreMotion"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("MediaPlayer"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ApplicationServices"),
            ]
        )
    ]
)
