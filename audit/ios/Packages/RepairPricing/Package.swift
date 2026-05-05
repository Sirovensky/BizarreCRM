// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RepairPricing",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RepairPricing", targets: ["RepairPricing"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Networking")
    ],
    targets: [
        .target(
            name: "RepairPricing",
            dependencies: ["Core", "DesignSystem", "Networking"]
        ),
        .testTarget(
            name: "RepairPricingTests",
            dependencies: ["RepairPricing", "Networking"]
        )
    ]
)
