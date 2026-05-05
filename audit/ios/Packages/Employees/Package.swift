// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Employees",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Employees", targets: ["Employees"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Networking"),
        .package(path: "../Persistence"),
        .package(path: "../Sync")
    ],
    targets: [
        .target(
            name: "Employees",
            dependencies: ["Core", "DesignSystem", "Networking", "Persistence", "Sync"]
        ),
        .testTarget(
            name: "EmployeesTests",
            dependencies: ["Employees", "Networking"],
            path: "Tests/EmployeesTests"
        )
    ]
)
