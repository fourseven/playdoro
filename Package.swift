// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Plexodoro",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "PlexodoroKit", targets: ["PlexodoroKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
    ],
    targets: [
        .target(
            name: "PlexodoroKit",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .executableTarget(
            name: "Plexodoro",
            dependencies: [
                "PlexodoroKit",
            ],
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "PlexodoroTests",
            dependencies: [
                "PlexodoroKit",
            ]
        ),
    ]
)
