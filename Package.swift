// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OrpheusUIApp",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(
            url: "https://github.com/Blaizzy/mlx-audio-swift.git",
            branch: "main"
        )
    ],
    targets: [
        .executableTarget(
            name: "OrpheusUIApp",
            dependencies: [
                .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
                .product(name: "MLXAudioTTS", package: "mlx-audio-swift")
            ]
        )
    ]
)
