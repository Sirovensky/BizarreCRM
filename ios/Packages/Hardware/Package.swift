// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hardware",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Hardware", targets: ["Hardware"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../Persistence")
    ],
    targets: [
        .target(name: "Hardware", dependencies: ["Core", "Persistence"]),
        .testTarget(name: "HardwareTests", dependencies: ["Hardware"])
    ]
)
