// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FieldService",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FieldService", targets: ["FieldService"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Networking"),
        .package(path: "../Appointments")
    ],
    targets: [
        .target(
            name: "FieldService",
            dependencies: ["Core", "DesignSystem", "Networking", "Appointments"]
        ),
        .testTarget(
            name: "FieldServiceTests",
            dependencies: ["FieldService", "Core", "Networking"],
            path: "Tests/FieldServiceTests"
        )
    ]
)
