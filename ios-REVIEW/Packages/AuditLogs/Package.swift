// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AuditLogs",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AuditLogs", targets: ["AuditLogs"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Networking")
    ],
    targets: [
        .target(
            name: "AuditLogs",
            dependencies: ["Core", "DesignSystem", "Networking"]
        ),
        .testTarget(
            name: "AuditLogsTests",
            dependencies: ["AuditLogs", "Core", "Networking"],
            path: "Tests/AuditLogsTests"
        )
    ]
)
