// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Invoices",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Invoices", targets: ["Invoices"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Networking"),
        .package(path: "../Persistence")
    ],
    targets: [
        .target(
            name: "Invoices",
            dependencies: ["Core", "DesignSystem", "Networking", "Persistence"]
        )
    ]
)
