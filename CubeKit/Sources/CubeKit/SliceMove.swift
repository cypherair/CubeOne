/// A middle-layer turn in standard notation: M (between L and R, turns
/// like L), E (between U and D, turns like D), S (between F and B,
/// turns like F).
///
/// `CubeState` keeps centers fixed, so a slice turn is represented as
/// the equivalent pair of outer-layer turns; the renderer adds a
/// compensating whole-cube reorientation so the user sees the true
/// middle slice rotate.
public enum SliceMove: Int, CaseIterable, Hashable, Sendable, Codable {
    case m, m2, mPrime
    case e, e2, ePrime
    case s, s2, sPrime

    /// 0 = M (x axis), 1 = E (y axis), 2 = S (z axis).
    public var axisIndex: Int { rawValue / 3 }

    /// 1 = 90° in the slice's own direction, 2 = 180°, 3 = 270°.
    public var quarterTurns: Int { rawValue % 3 + 1 }

    public init?(axisIndex: Int, quarterTurns: Int) {
        guard (0...2).contains(axisIndex), (1...3).contains(quarterTurns) else { return nil }
        self.init(rawValue: axisIndex * 3 + quarterTurns - 1)
    }

    public var inverse: SliceMove {
        SliceMove(axisIndex: axisIndex, quarterTurns: 4 - quarterTurns)!
    }

    /// The outer-layer pair whose effect on a fixed-center cube equals
    /// this slice turn (modulo the whole-cube reorientation).
    public var equivalentOuterMoves: [Move] {
        switch self {
        case .m: [Move](notation: "L' R")!
        case .m2: [Move](notation: "L2 R2")!
        case .mPrime: [Move](notation: "L R'")!
        case .e: [Move](notation: "U D'")!
        case .e2: [Move](notation: "U2 D2")!
        case .ePrime: [Move](notation: "U' D")!
        case .s: [Move](notation: "F' B")!
        case .s2: [Move](notation: "F2 B2")!
        case .sPrime: [Move](notation: "F B'")!
        }
    }

    /// Signed quarter turns of the slice's rotation about the positive
    /// axis (x for M, y for E, z for S) — also the frame compensation
    /// the renderer applies. M and E turn positively, S negatively.
    public var signedQuarterTurns: Int {
        let sign = axisIndex == 2 ? -1 : 1
        return sign * (quarterTurns == 3 ? -1 : quarterTurns)
    }

    public var notation: String {
        let letter = ["M", "E", "S"][axisIndex]
        switch quarterTurns {
        case 1: return letter
        case 2: return letter + "2"
        default: return letter + "'"
        }
    }

    public init?(notation: String) {
        guard let first = notation.first,
              let axis = ["M": 0, "E": 1, "S": 2][String(first)] else { return nil }
        let turns: Int
        switch notation.dropFirst() {
        case "": turns = 1
        case "2": turns = 2
        case "'": turns = 3
        default: return nil
        }
        self.init(axisIndex: axis, quarterTurns: turns)
    }
}

extension SliceMove: CustomStringConvertible {
    public var description: String { notation }
}

extension CubeState {
    /// Applies the fixed-center equivalent of a slice turn.
    public func applying(_ slice: SliceMove) -> CubeState {
        applying(slice.equivalentOuterMoves)
    }
}
