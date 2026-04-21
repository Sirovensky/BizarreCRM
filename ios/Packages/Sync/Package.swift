// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sync",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Sync", targets: ["Sync"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../Networking"),
        .package(path: "../Persistence"),
        .package(path: "../DesignSystem"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.3")
    ],
    targets: [
        .target(
            name: "Sync",
            dependencies: [
                "Core",
                "Networking",
                "Persistence",
                "DesignSystem",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "SyncTests",
            dependencies: ["Sync", "Core", "Persistence"]
        )
    ]
)
