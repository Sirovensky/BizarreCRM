// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Appointments",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Appointments", targets: ["Appointments"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../Customers"),
        .package(path: "../DesignSystem"),
        .package(path: "../Networking"),
        .package(path: "../Persistence"),
        .package(path: "../Sync")
    ],
    targets: [
        .target(
            name: "Appointments",
            dependencies: ["Core", "Customers", "DesignSystem", "Networking", "Persistence", "Sync"]
        ),
        .testTarget(
            name: "AppointmentsTests",
            dependencies: ["Appointments", "Networking"],
            path: "Tests/AppointmentsTests"
        )
    ]
)
