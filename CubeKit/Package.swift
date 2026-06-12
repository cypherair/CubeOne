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
        .executable(name: "cubekit-bake", targets: ["CubeKitBake"]),
    ],
    targets: [
        .target(name: "CubeKit"),
        .executableTarget(name: "CubeKitBake", dependencies: ["CubeKit"]),
        .testTarget(name: "CubeKitTests", dependencies: ["CubeKit"]),
    ]
)
