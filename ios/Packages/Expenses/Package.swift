// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Expenses",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Expenses", targets: ["Expenses"])
    ],
    dependencies: [
        .package(path: "../Camera"),
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Networking"),
        .package(path: "../Persistence")
    ],
    targets: [
        .target(
            name: "Expenses",
            dependencies: ["Camera", "Core", "DesignSystem", "Networking", "Persistence"]
        ),
        .testTarget(
            name: "ExpensesTests",
            dependencies: ["Expenses", "Core", "Networking"],
            path: "Tests/ExpensesTests"
        )
    ]
)
