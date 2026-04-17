// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Auth",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Auth", targets: ["Auth"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Networking"),
        .package(path: "../Persistence")
    ],
    targets: [
        .target(
            name: "Auth",
            dependencies: ["Core", "DesignSystem", "Networking", "Persistence"]
        ),
        .testTarget(
            name: "AuthTests",
            dependencies: ["Auth"]
        )
    ]
)
