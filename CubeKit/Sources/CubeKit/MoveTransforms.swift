/// Shared move-sequence utilities used by the staged solvers.
extension Array where Element == Move {
    /// Conjugates the sequence by k whole-cube y-rotations: the
    /// algorithm performed as if the cube had been rotated about the U
    /// axis. One y step maps the face that was Front to where U sends
    /// front pieces: F→L→B→R (U and D unchanged), so slot indices
    /// (corners urf→ufl→ulb→ubr, edges ur→uf→ul→ub, fr→fl→bl→br)
    /// shift by +k, matching the U-turn piece cycle.
    func rotatedY(times: Int) -> [Move] {
        let k = ((times % 4) + 4) % 4
        guard k > 0 else { return self }
        let map: [Face: Face] = [.front: .left, .left: .back, .back: .right, .right: .front]
        var result = self
        for _ in 0..<k {
            result = result.map { move in
                if let mapped = map[move.face] {
                    return Move(face: mapped, quarterTurns: move.quarterTurns)
                }
                return move
            }
        }
        return result
    }

    /// Merges adjacent same-face turns (R R → R2, R R' → nothing).
    func merged() -> [Move] {
        var result: [Move] = []
        for move in self {
            if let last = result.last, last.face == move.face {
                let turns = (last.quarterTurns + move.quarterTurns) % 4
                result.removeLast()
                if turns != 0 {
                    result.append(Move(face: move.face, quarterTurns: turns))
                }
            } else {
                result.append(move)
            }
        }
        return result
    }
}

/// Per-move actions on a single tracked piece, encoded as
/// `slot * orientations + orientation`. Used by the search-based solver
/// stages, which track only the pieces they care about.
enum PieceAction {
    /// edge[move][slot*2+ori] = newSlot*2 + newOri
    static let edge: [[Int]] = Move.allCases.map { move in
        let cube = CubeState.solved.applying(move)
        var table = [Int](repeating: 0, count: 24)
        for slot in 0..<12 {
            // The piece that was at `from` is now at `slot`.
            let from = cube.edgePermutation[slot]
            for ori in 0..<2 {
                table[from * 2 + ori] = slot * 2 + ((ori + cube.edgeOrientation[slot]) % 2)
            }
        }
        return table
    }

    /// corner[move][slot*3+ori] = newSlot*3 + newOri
    static let corner: [[Int]] = Move.allCases.map { move in
        let cube = CubeState.solved.applying(move)
        var table = [Int](repeating: 0, count: 24)
        for slot in 0..<8 {
            let from = cube.cornerPermutation[slot]
            for ori in 0..<3 {
                table[from * 3 + ori] = slot * 3 + ((ori + cube.cornerOrientation[slot]) % 3)
            }
        }
        return table
    }

    /// The action of a whole move sequence on edge codes.
    static func edgeAction(of moves: [Move]) -> [Int] {
        var table = Array(0..<24)
        for move in moves {
            let action = edge[move.rawValue]
            table = table.map { action[$0] }
        }
        return table
    }

    /// The action of a whole move sequence on corner codes.
    static func cornerAction(of moves: [Move]) -> [Int] {
        var table = Array(0..<24)
        for move in moves {
            let action = corner[move.rawValue]
            table = table.map { action[$0] }
        }
        return table
    }
}
