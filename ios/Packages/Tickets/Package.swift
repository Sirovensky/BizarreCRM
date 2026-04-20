// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tickets",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Tickets", targets: ["Tickets"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Networking"),
        .package(path: "../Persistence"),
        .package(path: "../Customers")
    ],
    targets: [
        .target(
            name: "Tickets",
            dependencies: ["Core", "DesignSystem", "Networking", "Persistence", "Customers"]
        ),
        .testTarget(
            name: "TicketsTests",
            dependencies: ["Tickets", "Networking", "Persistence"]
        )
    ]
)
