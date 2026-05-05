// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KioskMode",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "KioskMode", targets: ["KioskMode"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Networking"),
        .package(path: "../Persistence")
    ],
    targets: [
        .target(
            name: "KioskMode",
            dependencies: [
                "Core",
                "DesignSystem",
                "Networking",
                "Persistence"
            ]
        ),
        .testTarget(
            name: "KioskModeTests",
            dependencies: ["KioskMode", "Networking"]
        )
    ]
)
