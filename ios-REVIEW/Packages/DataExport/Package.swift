// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DataExport",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DataExport", targets: ["DataExport"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Networking")
    ],
    targets: [
        .target(
            name: "DataExport",
            dependencies: ["Core", "DesignSystem", "Networking"]
        ),
        .testTarget(
            name: "DataExportTests",
            dependencies: ["DataExport", "Core", "Networking"],
            path: "Tests/DataExportTests"
        )
    ]
)
