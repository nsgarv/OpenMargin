// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "OpenMargin",
    platforms: [.macOS(.v27)],
    products: [
        .executable(name: "OpenMargin", targets: ["OpenMargin"])
    ],
    targets: [
        .target(name: "OpenMarginCore"),
        .executableTarget(
            name: "OpenMargin",
            dependencies: ["OpenMarginCore"]
        ),
        .testTarget(
            name: "OpenMarginCoreTests",
            dependencies: ["OpenMarginCore"]
        )
    ]
)
