// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CommandPalette",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CommandPalette", targets: ["CommandPalette"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem")
    ],
    targets: [
        .target(
            name: "CommandPalette",
            dependencies: ["Core", "DesignSystem"]
        ),
        .testTarget(
            name: "CommandPaletteTests",
            dependencies: ["CommandPalette"]
        )
    ]
)
