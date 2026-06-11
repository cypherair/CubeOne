/// One of the six faces of the cube.
///
/// The raw-value order (U, R, F, D, L, B) is the standard facelet and
/// notation order used throughout CubeKit; a face also doubles as the
/// sticker color of its center in the solved orientation.
public enum Face: Int, CaseIterable, Hashable, Sendable, Codable {
    case up, right, front, down, left, back

    public var letter: Character {
        switch self {
        case .up: "U"
        case .right: "R"
        case .front: "F"
        case .down: "D"
        case .left: "L"
        case .back: "B"
        }
    }

    public init?(letter: Character) {
        switch letter {
        case "U", "u": self = .up
        case "R", "r": self = .right
        case "F", "f": self = .front
        case "D", "d": self = .down
        case "L", "l": self = .left
        case "B", "b": self = .back
        default: return nil
        }
    }
}

/// A face turn in half-turn metric: 90° clockwise, 180°, or 90°
/// counterclockwise. Raw values 0...17 index the solver's move tables.
public enum Move: Int, CaseIterable, Hashable, Sendable, Codable {
    case u, u2, uPrime
    case r, r2, rPrime
    case f, f2, fPrime
    case d, d2, dPrime
    case l, l2, lPrime
    case b, b2, bPrime

    public init(face: Face, quarterTurns: Int) {
        precondition((1...3).contains(quarterTurns), "quarterTurns must be 1, 2, or 3")
        self.init(rawValue: face.rawValue * 3 + quarterTurns - 1)!
    }

    public var face: Face { Face(rawValue: rawValue / 3)! }

    /// 1 = 90° clockwise, 2 = 180°, 3 = 90° counterclockwise.
    public var quarterTurns: Int { rawValue % 3 + 1 }

    public var inverse: Move { Move(face: face, quarterTurns: 4 - quarterTurns) }

    public var notation: String {
        let suffix: String
        switch quarterTurns {
        case 1: suffix = ""
        case 2: suffix = "2"
        default: suffix = "'"
        }
        return String(face.letter) + suffix
    }

    public init?(notation: String) {
        guard let first = notation.first, let face = Face(letter: first) else { return nil }
        switch notation.dropFirst() {
        case "": self = Move(face: face, quarterTurns: 1)
        case "2": self = Move(face: face, quarterTurns: 2)
        case "'": self = Move(face: face, quarterTurns: 3)
        default: return nil
        }
    }
}

extension Move: CustomStringConvertible {
    public var description: String { notation }
}

extension Array where Element == Move {
    /// Parses space-separated cube notation like `"R U R' U2"`.
    public init?(notation: String) {
        var moves: [Move] = []
        for token in notation.split(whereSeparator: \.isWhitespace) {
            guard let move = Move(notation: String(token)) else { return nil }
            moves.append(move)
        }
        self = moves
    }

    public var notation: String { map(\.notation).joined(separator: " ") }

    /// The sequence that exactly undoes this one.
    public var inverse: [Move] { reversed().map(\.inverse) }
}
