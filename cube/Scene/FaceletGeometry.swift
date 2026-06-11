import CubeKit
import simd

/// Pure math relating CubeKit's 54 facelet indices to 3D cube geometry.
///
/// Grid coordinates: each cubelet sits at (x, y, z) ∈ {-1, 0, 1}³ with
/// x toward R, y toward U, z toward F. Facelet rows/columns follow
/// CubeKit's reading order (looking straight at each face).
nonisolated enum FaceletGeometry {
    struct Placement {
        let faceletIndex: Int
        let face: Face
        let gridPosition: SIMD3<Int>
    }

    static func placement(for faceletIndex: Int) -> Placement {
        let face = Face(rawValue: faceletIndex / 9)!
        let row = (faceletIndex % 9) / 3
        let column = faceletIndex % 3
        let grid: SIMD3<Int>
        switch face {
        case .up: grid = [column - 1, 1, row - 1]
        case .right: grid = [1, 1 - row, 1 - column]
        case .front: grid = [column - 1, 1 - row, 1]
        case .down: grid = [column - 1, -1, 1 - row]
        case .left: grid = [-1, 1 - row, column - 1]
        case .back: grid = [1 - column, 1 - row, -1]
        }
        return Placement(faceletIndex: faceletIndex, face: face, gridPosition: grid)
    }

    static let allPlacements: [Placement] = (0..<54).map(placement(for:))

    /// The move described by turning `layer` (the signed grid component
    /// along `axis`) with rotation sense `rotationSign` (sign of the
    /// angle about the positive axis).
    static func move(axis: Int, layer: Int, rotationSign: Int) -> Move? {
        guard abs(layer) == 1 else { return nil }
        let face: Face
        switch (axis, layer > 0) {
        case (0, true): face = .right
        case (0, false): face = .left
        case (1, true): face = .up
        case (1, false): face = .down
        case (2, true): face = .front
        case (2, false): face = .back
        default: return nil
        }
        // A face's clockwise turn is a negative rotation about its own
        // outward normal, so about the positive axis the sense flips
        // with the layer sign.
        let clockwise = rotationSign != layer
        return Move(face: face, quarterTurns: clockwise ? 1 : 3)
    }

    /// Rotation (about the positive `axis`, in quarter turns of signed
    /// direction) that a move performs, for animating.
    static func rotation(for move: Move) -> (axis: SIMD3<Float>, angle: Float, layer: Int) {
        let normal = move.face.normal
        // Clockwise viewed from outside the face = negative angle about
        // the outward normal.
        let quarter = -Float.pi / 2
        let angle: Float
        switch move.quarterTurns {
        case 1: angle = quarter
        case 2: angle = 2 * quarter
        default: angle = -quarter
        }
        let axisIndex = Self.axisIndex(of: normal)
        let layer = normal[axisIndex] > 0 ? 1 : -1
        var axis = SIMD3<Float>(repeating: 0)
        axis[axisIndex] = 1
        return (axis, angle * (normal[axisIndex] > 0 ? 1 : -1), layer)
    }

    static func axisIndex(of vector: SIMD3<Float>) -> Int {
        let absolute = abs(vector)
        if absolute.x >= absolute.y && absolute.x >= absolute.z { return 0 }
        return absolute.y >= absolute.z ? 1 : 2
    }

    /// Snaps a unit-ish vector to the nearest signed axis direction.
    static func snappedAxis(_ vector: SIMD3<Float>) -> SIMD3<Int> {
        let index = axisIndex(of: vector)
        var result = SIMD3<Int>(repeating: 0)
        result[index] = vector[index] >= 0 ? 1 : -1
        return result
    }
}
