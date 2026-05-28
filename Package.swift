// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Plexodoro",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/ReactiveX/RxSwift.git", from: "6.10.2"),
    ],
    targets: [
        .executableTarget(
            name: "Plexodoro",
            dependencies: [
                .product(name: "RxSwift", package: "RxSwift"),
                .product(name: "RxCocoa", package: "RxSwift"),
            ],
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "PlexodoroTests",
            dependencies: [
                "Plexodoro",
                .product(name: "RxSwift", package: "RxSwift"),
                .product(name: "RxTest", package: "RxSwift"),
            ]
        ),
    ]
)
