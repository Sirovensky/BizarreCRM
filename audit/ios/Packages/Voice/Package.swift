// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Voice",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Voice", targets: ["Voice"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Networking")
    ],
    targets: [
        .target(
            name: "Voice",
            dependencies: ["Core", "DesignSystem", "Networking"]
        ),
        .testTarget(
            name: "VoiceTests",
            dependencies: ["Voice", "Networking"]
        )
    ]
)
