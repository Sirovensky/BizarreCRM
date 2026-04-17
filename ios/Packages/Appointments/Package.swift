// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Appointments",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Appointments", targets: ["Appointments"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Networking"),
        .package(path: "../Persistence")
    ],
    targets: [
        .target(
            name: "Appointments",
            dependencies: ["Core", "DesignSystem", "Networking", "Persistence"]
        )
    ]
)
