/// Why a painted cube cannot exist on a real Rubik's cube.
public enum CubeValidationError: Error, Equatable, Sendable {
    /// Not exactly nine stickers of each color.
    case wrongColorCounts
    /// The six center stickers must be the six distinct colors in the
    /// standard arrangement (they are fixed on a real cube).
    case wrongCenters
    /// Some corner or edge has a sticker combination that exists on no
    /// real piece (e.g. two stickers of the same color).
    case unrecognizablePiece
    /// The same physical piece appears more than once.
    case duplicatePiece
    /// Total corner twist is not a multiple of three (a corner is twisted).
    case cornerTwist
    /// An odd number of edges is flipped.
    case edgeFlip
    /// Corner and edge permutations disagree in parity (two pieces are
    /// swapped — impossible to reach with face turns).
    case permutationParity
}

/// The 54-sticker view of a cube, used by the editor and renderer.
///
/// Sticker order: faces U, R, F, D, L, B; within each face, reading
/// order (row by row) while looking straight at that face.
public struct FaceletCube: Hashable, Sendable, Codable {
    public var stickers: [Face]

    public init(stickers: [Face]) {
        precondition(stickers.count == 54)
        self.stickers = stickers
    }

    public static let solved = FaceletCube(
        stickers: Face.allCases.flatMap { Array(repeating: $0, count: 9) }
    )

    /// The sticker index of a face's center.
    public static func centerIndex(of face: Face) -> Int { face.rawValue * 9 + 4 }

    public static func isCenter(_ stickerIndex: Int) -> Bool { stickerIndex % 9 == 4 }

    /// Sticker indices of each corner slot, starting with the U/D sticker
    /// and continuing clockwise around the piece (Kociemba convention).
    static let cornerFacelets: [[Int]] = [
        [8, 9, 20], [6, 18, 38], [0, 36, 47], [2, 45, 11],
        [29, 26, 15], [27, 44, 24], [33, 53, 42], [35, 17, 51],
    ]
    /// Solved colors of each corner piece, in the same sticker order.
    static let cornerColors: [[Face]] = [
        [.up, .right, .front], [.up, .front, .left], [.up, .left, .back], [.up, .back, .right],
        [.down, .front, .right], [.down, .left, .front], [.down, .back, .left], [.down, .right, .back],
    ]
    static let edgeFacelets: [[Int]] = [
        [5, 10], [7, 19], [3, 37], [1, 46], [32, 16], [28, 25],
        [30, 43], [34, 52], [23, 12], [21, 41], [50, 39], [48, 14],
    ]
    static let edgeColors: [[Face]] = [
        [.up, .right], [.up, .front], [.up, .left], [.up, .back],
        [.down, .right], [.down, .front], [.down, .left], [.down, .back],
        [.front, .right], [.front, .left], [.back, .left], [.back, .right],
    ]

    /// Renders a cubie-level state to stickers.
    public init(_ state: CubeState) {
        var stickers = FaceletCube.solved.stickers
        for slot in 0..<8 {
            let piece = state.cornerPermutation[slot]
            let twist = state.cornerOrientation[slot]
            for k in 0..<3 {
                stickers[Self.cornerFacelets[slot][(k + twist) % 3]] = Self.cornerColors[piece][k]
            }
        }
        for slot in 0..<12 {
            let piece = state.edgePermutation[slot]
            let flip = state.edgeOrientation[slot]
            for k in 0..<2 {
                stickers[Self.edgeFacelets[slot][(k + flip) % 2]] = Self.edgeColors[piece][k]
            }
        }
        self.stickers = stickers
    }

    /// Validates the stickers and returns the cubie-level state, or throws
    /// the specific reason the cube is impossible.
    public func validatedState() throws(CubeValidationError) -> CubeState {
        var counts = [Int](repeating: 0, count: 6)
        for sticker in stickers { counts[sticker.rawValue] += 1 }
        guard counts.allSatisfy({ $0 == 9 }) else { throw .wrongColorCounts }

        for face in Face.allCases {
            guard stickers[Self.centerIndex(of: face)] == face else { throw .wrongCenters }
        }

        var cornerPermutation = [Int](repeating: -1, count: 8)
        var cornerOrientation = [Int](repeating: 0, count: 8)
        for slot in 0..<8 {
            let facelets = Self.cornerFacelets[slot]
            // The U/D sticker fixes the twist; the next two clockwise
            // stickers then identify the piece.
            guard let twist = (0..<3).first(where: { k in
                let color = stickers[facelets[k]]
                return color == .up || color == .down
            }) else { throw .unrecognizablePiece }
            let primary = stickers[facelets[twist]]
            let second = stickers[facelets[(twist + 1) % 3]]
            let third = stickers[facelets[(twist + 2) % 3]]
            guard let piece = (0..<8).first(where: { p in
                Self.cornerColors[p] == [primary, second, third]
            }) else { throw .unrecognizablePiece }
            cornerPermutation[slot] = piece
            cornerOrientation[slot] = twist
        }
        guard Set(cornerPermutation).count == 8 else { throw .duplicatePiece }

        var edgePermutation = [Int](repeating: -1, count: 12)
        var edgeOrientation = [Int](repeating: 0, count: 12)
        for slot in 0..<12 {
            let facelets = Self.edgeFacelets[slot]
            let colors = [stickers[facelets[0]], stickers[facelets[1]]]
            if let piece = (0..<12).first(where: { Self.edgeColors[$0] == colors }) {
                edgePermutation[slot] = piece
                edgeOrientation[slot] = 0
            } else if let piece = (0..<12).first(where: { Self.edgeColors[$0] == colors.reversed() }) {
                edgePermutation[slot] = piece
                edgeOrientation[slot] = 1
            } else {
                throw .unrecognizablePiece
            }
        }
        guard Set(edgePermutation).count == 12 else { throw .duplicatePiece }

        guard cornerOrientation.reduce(0, +) % 3 == 0 else { throw .cornerTwist }
        guard edgeOrientation.reduce(0, +) % 2 == 0 else { throw .edgeFlip }
        guard permutationParity(cornerPermutation) == permutationParity(edgePermutation) else {
            throw .permutationParity
        }

        return CubeState(
            cornerPermutation: cornerPermutation, cornerOrientation: cornerOrientation,
            edgePermutation: edgePermutation, edgeOrientation: edgeOrientation
        )
    }
}

extension CubeState {
    /// The sticker view of this state.
    public var facelets: FaceletCube { FaceletCube(self) }
}
