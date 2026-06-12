import Foundation

/// The stages of a CFOP solve. F2L pairs are numbered by their slot
/// (1 = front-right, 2 = front-left, 3 = back-left, 4 = back-right);
/// the OLL and PLL stages carry the recognized case name.
public enum CFOPStage: Hashable, Sendable, SolverStage {
    case cross
    case f2lPair(Int)
    case oll(String)
    case pll(String)

    public var displayName: String {
        switch self {
        case .cross: "Cross"
        case .f2lPair(let slot): "F2L pair \(slot)"
        case .oll(let name): "OLL \(name)"
        case .pll(let name): name == "AUF" ? "Final turn" : "PLL · \(name)"
        }
    }
}

/// The speedcubing method: an optimal cross, four corner–edge pairs
/// inserted with the standard F2L triggers, then the full 57-case OLL
/// and 21-case PLL algorithm sets. Solutions run ~60 moves and read
/// the way a speedcuber would solve.
public struct CFOPSolver: Sendable {
    public init() {}

    public func solve(_ state: CubeState) -> StagedSolution<CFOPStage>? {
        guard state.isLegal else { return nil }
        var worker = Worker(state: state)
        do {
            try worker.run()
            return StagedSolution(stages: worker.finishedStages)
        } catch {
            assertionFailure("CFOP solver stuck: \(error)")
            return nil
        }
    }
}

// MARK: - Implementation

private enum SolverFailure: Error {
    case stuck(String)
}

private struct Worker {
    var state: CubeState
    var finishedStages: [StagedSolution<CFOPStage>.Stage] = []
    private var currentMoves: [Move] = []

    init(state: CubeState) {
        self.state = state
    }

    mutating func run() throws {
        try record(.cross) { try $0.solveCross() }

        // Pairs in greedy order: always insert the cheapest one next.
        var remaining = (0..<4).filter { !self.pairSolved($0) }
        while !remaining.isEmpty {
            var best: (pair: Int, path: [Move])?
            for pair in remaining {
                guard let path = pairPath(pair, unsolved: remaining) else {
                    throw SolverFailure.stuck("pair \(pair + 1)")
                }
                if best == nil || path.count < best!.path.count {
                    best = (pair, path)
                }
            }
            let chosen = best!
            record(.f2lPair(chosen.pair + 1)) { $0.perform(chosen.path) }
            guard pairSolved(chosen.pair) else {
                throw SolverFailure.stuck("pair \(chosen.pair + 1) not solved")
            }
            remaining.removeAll { $0 == chosen.pair }
        }

        if CFOPAlgorithms.ollPattern(of: state) != CFOPAlgorithms.orientedPattern {
            let (name, moves) = try recognizeOLL()
            record(.oll(name)) { $0.perform(moves) }
        }
        if !state.isSolved {
            let (name, moves) = try recognizePLL()
            record(.pll(name)) { $0.perform(moves) }
        }
        guard state.isSolved else { throw SolverFailure.stuck("end state not solved") }
    }

    private mutating func record(
        _ stage: CFOPStage, _ body: (inout Worker) throws -> Void
    ) rethrows {
        currentMoves = []
        try body(&self)
        let moves = currentMoves.merged()
        if !moves.isEmpty {
            finishedStages.append(.init(stage: stage, moves: moves))
        }
        currentMoves = []
    }

    private mutating func perform(_ moves: [Move]) {
        for move in moves {
            state.apply(move)
            currentMoves.append(move)
        }
    }

    // MARK: Piece queries

    private func edgeLocation(of piece: Int) -> (slot: Int, ori: Int) {
        let slot = state.edgePermutation.firstIndex(of: piece)!
        return (slot, state.edgeOrientation[slot])
    }

    private func cornerLocation(of piece: Int) -> (slot: Int, ori: Int) {
        let slot = state.cornerPermutation.firstIndex(of: piece)!
        return (slot, state.cornerOrientation[slot])
    }

    private func pairSolved(_ pair: Int) -> Bool {
        let corner = 4 + pair
        let edge = 8 + pair
        return state.cornerPermutation[corner] == corner
            && state.cornerOrientation[corner] == 0
            && state.edgePermutation[edge] == edge
            && state.edgeOrientation[edge] == 0
    }

    // MARK: Cross — whole-cross optimal from a distance table

    /// Exact distances for the four cross edges (pieces 4–7) over all
    /// 18 moves: P(12,4) · 2⁴ = 190,080 entries, built once per process.
    private static let crossDistances: [Int8] = {
        let positionCount = PartialPermutation.count(slots: 12, pieces: 4)
        let solved = PartialPermutation.rank([4, 5, 6, 7], slots: 12) * 16
        return TableBuilder.breadthFirstDistances(
            stateCount: positionCount * 16, moveCount: 18, starts: [solved]
        ) { index, move in
            let positions = PartialPermutation.unrank(index / 16, slots: 12, pieces: 4)
            let action = PieceAction.edge[move]
            var movedPositions = [Int](repeating: 0, count: 4)
            var orientations = 0
            for piece in 0..<4 {
                let code = action[positions[piece] * 2 + (index >> piece & 1)]
                movedPositions[piece] = code / 2
                orientations |= (code % 2) << piece
            }
            return PartialPermutation.rank(movedPositions, slots: 12) * 16 + orientations
        }
    }()

    private static func crossIndex(of state: CubeState) -> Int {
        var positions = [Int](repeating: 0, count: 4)
        var orientations = 0
        for piece in 0..<4 {
            let slot = state.edgePermutation.firstIndex(of: 4 + piece)!
            positions[piece] = slot
            orientations |= state.edgeOrientation[slot] << piece
        }
        return PartialPermutation.rank(positions, slots: 12) * 16 + orientations
    }

    /// Greedy descent: the 18-move set is closed under inverses, so a
    /// distance-reducing move always exists. Cross is ≤ 8 moves.
    private mutating func solveCross() throws {
        var distance = Int(Self.crossDistances[Self.crossIndex(of: state)])
        while distance > 0 {
            var stepped = false
            for move in Move.allCases {
                let next = state.applying(move)
                if Int(Self.crossDistances[Self.crossIndex(of: next)]) == distance - 1 {
                    perform([move])
                    distance -= 1
                    stepped = true
                    break
                }
            }
            guard stepped else { throw SolverFailure.stuck("cross") }
        }
    }

    // MARK: F2L — pair search over the standard trigger macros

    /// Pop-out triggers per slot (front-right, front-left, back-left,
    /// back-right): each disturbs only its own pair and the top layer
    /// (cross edges pass through and return).
    private static let slotTriggers: [[Move]] = [
        [Move](notation: "R U R' U'")!,
        [Move](notation: "F U F' U'")!,
        [Move](notation: "L U L' U'")!,
        [Move](notation: "B U B' U'")!,
    ]

    /// The standard inserts for the front-right slot; other slots use
    /// their y-conjugates.
    private static let baseInserts: [[Move]] = [
        [Move](notation: "R U R'")!,
        [Move](notation: "R U' R'")!,
        [Move](notation: "R U2 R'")!,
        [Move](notation: "F' U F")!,
        [Move](notation: "F' U' F")!,
        [Move](notation: "F' U2 F")!,
    ]

    private static let uTurns: [[Move]] = [
        [Move(face: .up, quarterTurns: 1)],
        [Move(face: .up, quarterTurns: 2)],
        [Move(face: .up, quarterTurns: 3)],
    ]

    /// Cheapest macro path (by move count) that homes the pair: a
    /// Dijkstra over the tracked corner+edge state (24 × 24 codes),
    /// with an alphabet of U turns, this slot's inserts, and pop-out
    /// triggers for the other unsolved slots. Every macro preserves
    /// the cross and all other solved pairs, so any path is clean.
    private func pairPath(_ pair: Int, unsolved: [Int]) -> [Move]? {
        var alphabet = Self.uTurns
        for insert in Self.baseInserts {
            alphabet.append(insert.rotatedY(times: pair))
        }
        for other in unsolved where other != pair {
            alphabet.append(Self.slotTriggers[other])
        }
        let cornerActions = alphabet.map { PieceAction.cornerAction(of: $0) }
        let edgeActions = alphabet.map { PieceAction.edgeAction(of: $0) }

        let cornerStart = cornerLocation(of: 4 + pair)
        let edgeStart = edgeLocation(of: 8 + pair)
        let start = (cornerStart.slot * 3 + cornerStart.ori) * 24
            + edgeStart.slot * 2 + edgeStart.ori
        let goal = ((4 + pair) * 3) * 24 + (8 + pair) * 2
        if start == goal { return [] }

        var cost = [Int](repeating: .max, count: 576)
        var parent = [(state: Int, macro: Int)?](repeating: nil, count: 576)
        var done = [Bool](repeating: false, count: 576)
        cost[start] = 0
        while true {
            var current = -1
            var currentCost = Int.max
            for id in 0..<576 where !done[id] && cost[id] < currentCost {
                current = id
                currentCost = cost[id]
            }
            if current < 0 { return nil }
            if current == goal { break }
            done[current] = true
            let cornerCode = current / 24
            let edgeCode = current % 24
            for (index, macro) in alphabet.enumerated() {
                let next = cornerActions[index][cornerCode] * 24 + edgeActions[index][edgeCode]
                let nextCost = currentCost + macro.count
                if nextCost < cost[next] {
                    cost[next] = nextCost
                    parent[next] = (current, index)
                }
            }
        }

        var path: [Move] = []
        var cursor = goal
        while cursor != start {
            guard let step = parent[cursor] else { return nil }
            path.append(contentsOf: alphabet[step.macro].reversed())
            cursor = step.state
        }
        return path.reversed()
    }

    // MARK: OLL and PLL recognition

    private func recognizeOLL() throws -> (name: String, moves: [Move]) {
        for setup in [[]] + Self.uTurns {
            let aligned = state.applying(setup)
            if let entry = CFOPAlgorithms.ollTable[CFOPAlgorithms.ollPattern(of: aligned)] {
                return (entry.name, setup + entry.moves)
            }
        }
        throw SolverFailure.stuck("OLL recognition")
    }

    private func recognizePLL() throws -> (name: String, moves: [Move]) {
        let aufs: [[Move]] = [[]] + Self.uTurns
        for setup in aufs {
            let aligned = state.applying(setup)
            if aligned.isSolved { return ("AUF", setup) }
            for entry in CFOPAlgorithms.pllMoves {
                let applied = aligned.applying(entry.moves)
                for final in aufs where applied.applying(final).isSolved {
                    return (entry.name, setup + entry.moves + final)
                }
            }
        }
        throw SolverFailure.stuck("PLL recognition")
    }
}
