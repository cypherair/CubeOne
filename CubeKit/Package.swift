// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CubeKit",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0"),
    ],
    products: [
        .library(name: "CubeKit", targets: ["CubeKit"]),
    ],
    targets: [
        .target(name: "CubeKit"),
        .testTarget(name: "CubeKitTests", dependencies: ["CubeKit"]),
    ]
)
