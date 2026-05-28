// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Plexodoro",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Plexodoro",
            exclude: ["Info.plist"]
        ),
    ]
)
