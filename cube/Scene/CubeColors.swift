import CubeKit
import RealityKit
import SwiftUI

#if os(macOS)
typealias PlatformColor = NSColor
#else
typealias PlatformColor = UIColor
#endif

nonisolated extension Face {
    /// Standard WCA color scheme: white up, green front, red right.
    var stickerColor: PlatformColor {
        switch self {
        case .up: PlatformColor.white
        case .right: PlatformColor(red: 0.85, green: 0.12, blue: 0.16, alpha: 1)
        case .front: PlatformColor(red: 0.06, green: 0.62, blue: 0.27, alpha: 1)
        case .down: PlatformColor(red: 1.0, green: 0.84, blue: 0.05, alpha: 1)
        case .left: PlatformColor(red: 0.95, green: 0.48, blue: 0.04, alpha: 1)
        case .back: PlatformColor(red: 0.05, green: 0.32, blue: 0.73, alpha: 1)
        }
    }

    var swiftUIColor: Color { Color(stickerColor) }

    /// Outward normal of this face in cube-local space (x right, y up,
    /// z toward the viewer).
    var normal: SIMD3<Float> {
        switch self {
        case .up: [0, 1, 0]
        case .right: [1, 0, 0]
        case .front: [0, 0, 1]
        case .down: [0, -1, 0]
        case .left: [-1, 0, 0]
        case .back: [0, 0, -1]
        }
    }
}

enum CubeMaterials {
    static func sticker(for face: Face) -> SimpleMaterial {
        SimpleMaterial(color: face.stickerColor, roughness: 0.35, isMetallic: false)
    }

    static let plastic = SimpleMaterial(
        color: PlatformColor(white: 0.07, alpha: 1), roughness: 0.45, isMetallic: false)
}
