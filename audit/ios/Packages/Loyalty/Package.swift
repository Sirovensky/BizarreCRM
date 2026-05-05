// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Loyalty",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Loyalty", targets: ["Loyalty"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Networking")
    ],
    targets: [
        .target(
            name: "Loyalty",
            dependencies: [
                "Core",
                "DesignSystem",
                "Networking"
            ]
        ),
        .testTarget(
            name: "LoyaltyTests",
            dependencies: ["Loyalty", "Networking"]
        )
    ]
)
