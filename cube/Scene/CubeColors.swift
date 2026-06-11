import CubeKit
import RealityKit
import SwiftUI

#if os(macOS)
typealias PlatformColor = NSColor
#else
typealias PlatformColor = UIColor
#endif

nonisolated extension Face {
    var displayName: String {
        switch self {
        case .up: "Top"
        case .right: "Right"
        case .front: "Front"
        case .down: "Bottom"
        case .left: "Left"
        case .back: "Back"
        }
    }

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
    static func sticker(_ color: PlatformColor) -> SimpleMaterial {
        SimpleMaterial(color: color, roughness: 0.35, isMetallic: false)
    }

    static let plastic = SimpleMaterial(
        color: PlatformColor(white: 0.07, alpha: 1), roughness: 0.45, isMetallic: false)
}
