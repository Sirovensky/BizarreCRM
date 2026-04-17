// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Core",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Core", targets: ["Core"])
    ],
    dependencies: [
        .package(url: "https://github.com/hmlongco/Factory.git", from: "2.4.3")
    ],
    targets: [
        .target(
            name: "Core",
            dependencies: [
                .product(name: "Factory", package: "Factory")
            ]
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core"]
        )
    ]
)
