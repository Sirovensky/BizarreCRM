// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Networking",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Networking", targets: ["Networking"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(url: "https://github.com/daltoniam/Starscream.git", from: "4.0.8")
    ],
    targets: [
        .target(
            name: "Networking",
            dependencies: [
                "Core",
                .product(name: "Starscream", package: "Starscream")
            ]
        ),
        .testTarget(
            name: "NetworkingTests",
            dependencies: ["Networking"]
        )
    ]
)
