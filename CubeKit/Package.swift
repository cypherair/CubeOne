// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CubeKit",
    // Pure Swift with no OS-26 API dependencies — kept low so tests and
    // the bake tool run on CI runners and older Macs.
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
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
