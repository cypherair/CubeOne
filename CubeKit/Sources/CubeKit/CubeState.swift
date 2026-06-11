/// The eight corner slots, named by their faces. Raw values follow the
/// standard Kociemba ordering.
public enum Corner: Int, CaseIterable, Hashable, Sendable, Codable {
    case urf, ufl, ulb, ubr, dfr, dlf, dbl, drb
}

/// The twelve edge slots. The four E-slice edges (FR, FL, BL, BR) come
/// last; the solver's slice coordinate relies on that.
public enum Edge: Int, CaseIterable, Hashable, Sendable, Codable {
    case ur, uf, ul, ub, dr, df, dl, db, fr, fl, bl, br
}

/// A cube position at the cubie level: which piece sits in each slot and
/// how it is twisted or flipped. This is the source of truth for all
/// cube logic; stickers (`FaceletCube`) are derived.
public struct CubeState: Hashable, Sendable, Codable {
    /// `cornerPermutation[slot]` is the corner piece occupying `slot`.
    public var cornerPermutation: [Int]
    /// Clockwise twist (0...2) of the piece in each corner slot.
    public var cornerOrientation: [Int]
    /// `edgePermutation[slot]` is the edge piece occupying `slot`.
    public var edgePermutation: [Int]
    /// Flip (0...1) of the piece in each edge slot.
    public var edgeOrientation: [Int]

    public init(
        cornerPermutation: [Int], cornerOrientation: [Int],
        edgePermutation: [Int], edgeOrientation: [Int]
    ) {
        precondition(cornerPermutation.count == 8 && cornerOrientation.count == 8)
        precondition(edgePermutation.count == 12 && edgeOrientation.count == 12)
        self.cornerPermutation = cornerPermutation
        self.cornerOrientation = cornerOrientation
        self.edgePermutation = edgePermutation
        self.edgeOrientation = edgeOrientation
    }

    public static let solved = CubeState(
        cornerPermutation: Array(0..<8),
        cornerOrientation: Array(repeating: 0, count: 8),
        edgePermutation: Array(0..<12),
        edgeOrientation: Array(repeating: 0, count: 12)
    )

    public var isSolved: Bool { self == .solved }

    /// The state reached by performing `other` after `self`, treating both
    /// as move sequences applied to a solved cube.
    public func composed(with other: CubeState) -> CubeState {
        var result = CubeState.solved
        for i in 0..<8 {
            let from = other.cornerPermutation[i]
            result.cornerPermutation[i] = cornerPermutation[from]
            result.cornerOrientation[i] = (cornerOrientation[from] + other.cornerOrientation[i]) % 3
        }
        for i in 0..<12 {
            let from = other.edgePermutation[i]
            result.edgePermutation[i] = edgePermutation[from]
            result.edgeOrientation[i] = (edgeOrientation[from] + other.edgeOrientation[i]) % 2
        }
        return result
    }

    /// The state that composes with `self` to give the solved cube.
    public var inverse: CubeState {
        var result = CubeState.solved
        for i in 0..<8 { result.cornerPermutation[cornerPermutation[i]] = i }
        for i in 0..<8 {
            result.cornerOrientation[i] = (3 - cornerOrientation[result.cornerPermutation[i]]) % 3
        }
        for i in 0..<12 { result.edgePermutation[edgePermutation[i]] = i }
        for i in 0..<12 {
            result.edgeOrientation[i] = edgeOrientation[result.edgePermutation[i]]
        }
        return result
    }

    public func applying(_ move: Move) -> CubeState {
        var result = self
        let base = Self.basicMoves[move.face.rawValue]
        for _ in 0..<move.quarterTurns {
            result = result.composed(with: base)
        }
        return result
    }

    public func applying(_ moves: some Sequence<Move>) -> CubeState {
        moves.reduce(self) { $0.applying($1) }
    }

    public mutating func apply(_ move: Move) {
        self = applying(move)
    }

    /// The six basic clockwise face turns as cube states (the permutation
    /// each applies to a solved cube), indexed by `Face.rawValue`.
    /// These are the standard Kociemba move definitions.
    static let basicMoves: [CubeState] = [
        // U
        CubeState(
            cornerPermutation: [3, 0, 1, 2, 4, 5, 6, 7],
            cornerOrientation: [0, 0, 0, 0, 0, 0, 0, 0],
            edgePermutation: [3, 0, 1, 2, 4, 5, 6, 7, 8, 9, 10, 11],
            edgeOrientation: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        // R
        CubeState(
            cornerPermutation: [4, 1, 2, 0, 7, 5, 6, 3],
            cornerOrientation: [2, 0, 0, 1, 1, 0, 0, 2],
            edgePermutation: [8, 1, 2, 3, 11, 5, 6, 7, 4, 9, 10, 0],
            edgeOrientation: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        // F
        CubeState(
            cornerPermutation: [1, 5, 2, 3, 0, 4, 6, 7],
            cornerOrientation: [1, 2, 0, 0, 2, 1, 0, 0],
            edgePermutation: [0, 9, 2, 3, 4, 8, 6, 7, 1, 5, 10, 11],
            edgeOrientation: [0, 1, 0, 0, 0, 1, 0, 0, 1, 1, 0, 0]),
        // D
        CubeState(
            cornerPermutation: [0, 1, 2, 3, 5, 6, 7, 4],
            cornerOrientation: [0, 0, 0, 0, 0, 0, 0, 0],
            edgePermutation: [0, 1, 2, 3, 5, 6, 7, 4, 8, 9, 10, 11],
            edgeOrientation: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        // L
        CubeState(
            cornerPermutation: [0, 2, 6, 3, 4, 1, 5, 7],
            cornerOrientation: [0, 1, 2, 0, 0, 2, 1, 0],
            edgePermutation: [0, 1, 10, 3, 4, 5, 9, 7, 8, 2, 6, 11],
            edgeOrientation: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        // B
        CubeState(
            cornerPermutation: [0, 1, 3, 7, 4, 5, 2, 6],
            cornerOrientation: [0, 0, 1, 2, 0, 0, 2, 1],
            edgePermutation: [0, 1, 2, 11, 4, 5, 6, 10, 8, 9, 3, 7],
            edgeOrientation: [0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 1]),
    ]
}

func permutationParity(_ permutation: [Int]) -> Int {
    var inversions = 0
    for i in 0..<permutation.count {
        for j in (i + 1)..<permutation.count where permutation[i] > permutation[j] {
            inversions += 1
        }
    }
    return inversions % 2
}
