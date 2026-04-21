// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RolesEditor",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RolesEditor", targets: ["RolesEditor"])
    ],
    dependencies: [
        .package(url: "https://github.com/hmlongco/Factory.git", from: "2.4.3"),
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Networking")
    ],
    targets: [
        .target(
            name: "RolesEditor",
            dependencies: [
                .product(name: "Factory", package: "Factory"),
                .product(name: "Core", package: "Core"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "Networking", package: "Networking")
            ]
        ),
        .testTarget(
            name: "RolesEditorTests",
            dependencies: ["RolesEditor"]
        )
    ]
)
