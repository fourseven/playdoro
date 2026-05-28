// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Plexodoro",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    dependencies: [
        .package(url: "git@github.com:apple/swift-log.git", from: "1.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "Plexodoro",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ],
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "PlexodoroTests",
            dependencies: [
                "Plexodoro",
            ]
        ),
    ]
)
