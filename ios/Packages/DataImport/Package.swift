// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DataImport",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DataImport", targets: ["DataImport"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Networking")
    ],
    targets: [
        .target(
            name: "DataImport",
            dependencies: ["Core", "DesignSystem", "Networking"]
        ),
        .testTarget(
            name: "DataImportTests",
            dependencies: ["DataImport", "Core", "Networking"],
            path: "Tests/DataImportTests"
        )
    ]
)
