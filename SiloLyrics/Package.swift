// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SiloLyricsKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SiloLyricsKit", targets: ["SiloLyricsKit"]),
    ],
    targets: [
        .target(name: "SiloLyricsKit"),
        .testTarget(name: "SiloLyricsKitTests", dependencies: ["SiloLyricsKit"]),
    ]
)
