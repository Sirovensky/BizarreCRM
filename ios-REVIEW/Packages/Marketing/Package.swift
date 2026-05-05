// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Marketing",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Marketing", targets: ["Marketing"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Networking")
    ],
    targets: [
        .target(
            name: "Marketing",
            dependencies: ["Core", "DesignSystem", "Networking"]
        ),
        .testTarget(
            name: "MarketingTests",
            dependencies: ["Marketing", "Networking"]
        )
    ]
)
