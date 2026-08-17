// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Playdoro",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "PlaydoroKit", targets: ["PlaydoroKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
    ],
    targets: [
        .target(
            name: "PlaydoroKit",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ],
            resources: [
                .copy("Resources/EQPresets")
            ]
        ),
        .executableTarget(
            name: "Playdoro",
            dependencies: [
                "PlaydoroKit",
            ],
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "PlaydoroTests",
            dependencies: [
                "PlaydoroKit",
            ]
        ),
    ]
)