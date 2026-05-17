// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Timeclock",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Timeclock", targets: ["Timeclock"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Networking"),
        .package(path: "../Persistence")
    ],
    targets: [
        .target(
            name: "Timeclock",
            dependencies: ["Core", "DesignSystem", "Networking", "Persistence"]
        ),
        .testTarget(
            name: "TimeclockTests",
            dependencies: ["Timeclock", "Networking"]
        )
    ]
)
