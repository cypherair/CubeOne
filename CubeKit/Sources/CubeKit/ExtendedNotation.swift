/// Parses extended cube notation — wide turns (r u f l d b), slice
/// turns (M E S), and whole-cube rotations (x y z) — into plain outer
/// face turns, so standard algorithm sheets can be transcribed
/// verbatim while solvers keep emitting outer turns only.
///
/// A wide or slice turn is its outer-turn equivalent plus a whole-cube
/// reorientation (the same equivalences the scene uses for M/E/S);
/// the parser tracks the cumulative reorientation and rewrites every
/// later letter through it. The net reorientation at the end must be
/// the identity or a pure y-rotation: y keeps the U axis, so "first
/// two layers" and "last-layer orientation" statements survive it,
/// anything else would silently change what the algorithm means.
enum ExtendedNotation {
    /// Letter substitutions for one quarter of each rotation:
    /// algorithm letter → the face it lands on. Derived from the
    /// positional cycles (y follows U: F→L→B→R; x follows R: F→U→B→D;
    /// z follows F: U→R→D→L) — the letter map is the inverse cycle.
    private static let yMap: [Face: Face] = [
        .front: .right, .right: .back, .back: .left, .left: .front,
    ]
    private static let xMap: [Face: Face] = [
        .up: .front, .front: .down, .down: .back, .back: .up,
    ]
    private static let zMap: [Face: Face] = [
        .up: .left, .left: .down, .down: .right, .right: .up,
    ]

    private struct Frame {
        /// Maps an algorithm-frame face to the absolute face to turn.
        private var map: [Face] = Face.allCases

        func absolute(_ face: Face) -> Face { map[face.rawValue] }

        /// Applies `quarters` quarter-turns of a base rotation map.
        mutating func rotate(_ rotation: [Face: Face], quarters: Int) {
            for _ in 0..<(((quarters % 4) + 4) % 4) {
                map = Face.allCases.map { absolute(rotation[$0] ?? $0) }
            }
        }

        var isIdentity: Bool { map == Face.allCases }
        /// True when the residual rotation keeps the U axis in place.
        var isPureY: Bool { map[Face.up.rawValue] == .up && map[Face.down.rawValue] == .down }
    }

    /// Parses `notation`; returns nil for unknown tokens or when the
    /// net reorientation tilts the U axis.
    static func moves(_ notation: String) -> [Move]? {
        var frame = Frame()
        var moves: [Move] = []

        func emit(_ face: Face, _ quarters: Int) {
            moves.append(Move(face: frame.absolute(face), quarterTurns: quarters))
        }

        for token in notation.split(whereSeparator: \.isWhitespace) {
            guard let letter = token.first else { return nil }
            let quarters: Int
            switch token.dropFirst() {
            case "": quarters = 1
            case "2": quarters = 2
            case "'", "’": quarters = 3
            case "2'", "'2": quarters = 2
            default: return nil
            }

            switch letter {
            case "U", "R", "F", "D", "L", "B":
                emit(Face(letter: letter)!, quarters)
            case "x":
                frame.rotate(xMap, quarters: quarters)
            case "y":
                frame.rotate(yMap, quarters: quarters)
            case "z":
                frame.rotate(zMap, quarters: quarters)
            // Wide turn = opposite outer face + rotation: r = L then x.
            case "u":
                emit(.down, quarters)
                frame.rotate(yMap, quarters: quarters)
            case "r":
                emit(.left, quarters)
                frame.rotate(xMap, quarters: quarters)
            case "f":
                emit(.back, quarters)
                frame.rotate(zMap, quarters: quarters)
            case "d":
                emit(.up, quarters)
                frame.rotate(yMap, quarters: -quarters)
            case "l":
                emit(.right, quarters)
                frame.rotate(xMap, quarters: -quarters)
            case "b":
                emit(.front, quarters)
                frame.rotate(zMap, quarters: -quarters)
            // Slice turns, per the fixed-center equivalences:
            // M ≙ L' R + x', E ≙ U D' + y', S ≙ F' B + z.
            case "M":
                for _ in 0..<quarters {
                    emit(.left, 3)
                    emit(.right, 1)
                    frame.rotate(xMap, quarters: -1)
                }
            case "E":
                for _ in 0..<quarters {
                    emit(.up, 1)
                    emit(.down, 3)
                    frame.rotate(yMap, quarters: -1)
                }
            case "S":
                for _ in 0..<quarters {
                    emit(.front, 3)
                    emit(.back, 1)
                    frame.rotate(zMap, quarters: 1)
                }
            default:
                return nil
            }
        }

        guard frame.isPureY else { return nil }
        return moves.merged()
    }
}
