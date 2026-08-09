// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KoyomiCore",
    defaultLocalization: "ja",
    platforms: [
        .iOS(.v26),
        .macOS(.v15)
    ],
    products: [
        .library(name: "KoyomiCore", targets: ["KoyomiCore"])
    ],
    targets: [
        .target(
            name: "KoyomiCore",
            path: "Shared"
        ),
        .testTarget(
            name: "KoyomiCoreTests",
            dependencies: ["KoyomiCore"],
            path: "KoyomiTests"
        )
    ]
)
