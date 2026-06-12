/// The stages of the classic layer-by-layer (beginner) method, in order.
public enum BeginnerStage: String, CaseIterable, Sendable, SolverStage {
    case bottomCross
    case bottomCorners
    case middleEdges
    case topCross
    case permuteCorners
    case orientCorners
    case permuteEdges

    public var displayName: String {
        switch self {
        case .bottomCross: "Bottom cross"
        case .bottomCorners: "Bottom corners"
        case .middleEdges: "Middle edges"
        case .topCross: "Top cross"
        case .permuteCorners: "Corners in place"
        case .orientCorners: "Orient corners"
        case .permuteEdges: "Final edges"
        }
    }
}

/// Solves the way people are taught to: layer by layer, with short
/// memorable algorithms. Solutions are long (~150–250 moves) but every
/// stage has a understandable goal — the point is to follow along.
public struct BeginnerSolver: Sendable {
    public init() {}

    public func solve(_ state: CubeState) -> StagedSolution<BeginnerStage>? {
        guard state.isLegal else { return nil }
        var worker = Worker(state: state)
        do {
            try worker.run()
            return StagedSolution(stages: worker.finishedStages)
        } catch {
            assertionFailure("beginner solver stuck: \(error)")
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
    var finishedStages: [StagedSolution<BeginnerStage>.Stage] = []
    private var currentMoves: [Move] = []

    init(state: CubeState) {
        self.state = state
    }

    mutating func run() throws {
        try stage(.bottomCross) { try $0.solveBottomCross() }
        try stage(.bottomCorners) { try $0.solveBottomCorners() }
        try stage(.middleEdges) { try $0.solveMiddleEdges() }
        try stage(.topCross) { try $0.solveTopCross() }
        try stage(.permuteCorners) { try $0.permuteTopCorners() }
        try stage(.orientCorners) { try $0.orientTopCorners() }
        try stage(.permuteEdges) { try $0.permuteTopEdges() }
        guard state.isSolved else { throw SolverFailure.stuck("end state not solved") }
    }

    private mutating func stage(
        _ stage: BeginnerStage, _ body: (inout Worker) throws -> Void
    ) rethrows {
        currentMoves = []
        try body(&self)
        finishedStages.append(.init(stage: stage, moves: Self.merged(currentMoves)))
        currentMoves = []
    }

    /// Merges adjacent same-face turns (R R → R2, R R' → nothing).
    private static func merged(_ moves: [Move]) -> [Move] {
        var result: [Move] = []
        for move in moves {
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

    // MARK: Move plumbing

    private mutating func perform(_ moves: [Move]) {
        for move in moves {
            state.apply(move)
            currentMoves.append(move)
        }
    }

    private mutating func perform(_ notation: String) {
        perform([Move](notation: notation)!)
    }

    private mutating func performU(times: Int) {
        let k = ((times % 4) + 4) % 4
        if k > 0 { perform([Move(face: .up, quarterTurns: k)]) }
    }

    /// Conjugates a sequence by k whole-cube y-rotations: the algorithm
    /// performed as if the cube had been rotated about the U axis.
    /// Calibrated so that slot indices (corners urf→ufl→ulb→ubr, edges
    /// ur→uf→ul→ub) shift by +k, matching the U-turn piece cycle.
    private static func rotatedY(_ moves: [Move], times: Int) -> [Move] {
        let k = ((times % 4) + 4) % 4
        guard k > 0 else { return moves }
        // One y step maps the face that was Front to where U sends front
        // pieces: F→L→B→R→F (U and D unchanged).
        let map: [Face: Face] = [.front: .left, .left: .back, .back: .right, .right: .front]
        var result = moves
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

    // MARK: Piece queries

    private func edgeLocation(of piece: Int) -> (slot: Int, ori: Int) {
        let slot = state.edgePermutation.firstIndex(of: piece)!
        return (slot, state.edgeOrientation[slot])
    }

    private func cornerLocation(of piece: Int) -> (slot: Int, ori: Int) {
        let slot = state.cornerPermutation.firstIndex(of: piece)!
        return (slot, state.cornerOrientation[slot])
    }

    private func edgeSolved(_ piece: Int) -> Bool {
        state.edgePermutation[piece] == piece && state.edgeOrientation[piece] == 0
    }

    private func cornerSolved(_ piece: Int) -> Bool {
        state.cornerPermutation[piece] == piece && state.cornerOrientation[piece] == 0
    }

    // MARK: Per-move piece actions (for the searches)

    /// edgeAction[move][slot*2+ori] = newSlot*2 + newOri
    private static let edgeAction: [[Int]] = Move.allCases.map { move in
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

    private static func edgeCode(_ location: (slot: Int, ori: Int)) -> Int {
        location.slot * 2 + location.ori
    }

    // MARK: Stage 1 — bottom cross (search-based, no case tables)

    private mutating func solveBottomCross() throws {
        var solved: [Int] = []
        for piece in [5, 4, 7, 6] {  // df, dr, db, dl
            try searchCrossEdge(piece, preserving: solved)
            solved.append(piece)
        }
    }

    /// Breadth-first search over the tracked pieces only: bring `piece`
    /// home while every already-solved cross edge returns home.
    private mutating func searchCrossEdge(_ piece: Int, preserving: [Int]) throws {
        let tracked = [piece] + preserving
        let start = tracked.map { Self.edgeCode(edgeLocation(of: $0)) }
        let goal = tracked.map { $0 * 2 }
        if start == goal { return }

        func key(_ positions: [Int]) -> Int {
            positions.reduce(0) { $0 * 24 + $1 }
        }

        var parents: [Int: (key: Int, move: Move)] = [:]
        var queue: [[Int]] = [start]
        var visited: Set<Int> = [key(start)]
        var head = 0
        while head < queue.count {
            let positions = queue[head]
            head += 1
            for move in Move.allCases {
                let action = Self.edgeAction[move.rawValue]
                let next = positions.map { action[$0] }
                let nextKey = key(next)
                if visited.contains(nextKey) { continue }
                visited.insert(nextKey)
                parents[nextKey] = (key(positions), move)
                if next == goal {
                    var path: [Move] = [move]
                    var cursor = key(positions)
                    while let parent = parents[cursor] {
                        path.append(parent.move)
                        cursor = parent.key
                    }
                    perform(path.reversed())
                    return
                }
                queue.append(next)
            }
        }
        throw SolverFailure.stuck("cross edge \(piece)")
    }

    // MARK: Stage 2 — bottom corners

    private mutating func solveBottomCorners() throws {
        // Insert trigger per bottom slot: dfr, dlf, dbl, drb.
        let triggers = [
            [Move](notation: "R U R' U'")!,
            [Move](notation: "F U F' U'")!,
            [Move](notation: "L U L' U'")!,
            [Move](notation: "B U B' U'")!,
        ]
        for piece in 4...7 {
            if cornerSolved(piece) { continue }
            var location = cornerLocation(of: piece)
            // Stuck in the bottom layer (wrong slot or twisted): pop it
            // into the top layer with that slot's trigger.
            if location.slot >= 4 {
                perform(triggers[location.slot - 4])
                location = cornerLocation(of: piece)
            }
            guard location.slot < 4 else { throw SolverFailure.stuck("corner lift \(piece)") }
            // Park the corner directly above its slot (U moves slot i → i+1).
            let above = piece - 4
            performU(times: above - location.slot)
            // Repeat the slot's trigger until the corner drops in solved.
            var iterations = 0
            while !cornerSolved(piece) {
                perform(triggers[piece - 4])
                iterations += 1
                if iterations > 6 { throw SolverFailure.stuck("corner loop \(piece)") }
            }
        }
    }

    // MARK: Stage 3 — middle edges (macro search)

    /// The two standard inserts for the FR slot; variants for the other
    /// slots come from y-conjugation. Both preserve the first layer and
    /// the other middle slots (verified by tests).
    private static let insertMacros: [[Move]] = {
        let right = [Move](notation: "U R U' R' U' F' U F")!
        let left = [Move](notation: "U' F' U F U R U' R'")!
        var macros: [[Move]] = []
        for slot in 0..<4 {
            macros.append(Worker.rotatedY(right, times: slot))
            macros.append(Worker.rotatedY(left, times: slot))
        }
        return macros
    }()

    /// Maps middle-slot order fr, fl, bl, br to the y-conjugation count
    /// that maps slot fr onto it. fr=0; y sends fr→fl→bl→br (tested).
    private static let middleSlots = [8, 9, 10, 11]

    private mutating func solveMiddleEdges() throws {
        let uMoves: [[Move]] = [
            [Move(face: .up, quarterTurns: 1)],
            [Move(face: .up, quarterTurns: 2)],
            [Move(face: .up, quarterTurns: 3)],
        ]

        for piece in Self.middleSlots {
            if edgeSolved(piece) { continue }
            // An insert macro evicts whatever sits in its own slot, so
            // only macros for slots that aren't solved yet are allowed.
            var alphabet = uMoves
            for slotIndex in 0..<4 where !edgeSolved(Self.middleSlots[slotIndex]) {
                alphabet.append(Self.insertMacros[slotIndex * 2])
                alphabet.append(Self.insertMacros[slotIndex * 2 + 1])
            }
            // Each macro's action on a single tracked edge piece.
            let actions: [[Int]] = alphabet.map { macro in
                var table = Array(0..<24)
                for move in macro {
                    let action = Self.edgeAction[move.rawValue]
                    table = table.map { action[$0] }
                }
                return table
            }
            let start = Self.edgeCode(edgeLocation(of: piece))
            let goal = piece * 2
            var parents: [Int: (code: Int, macro: Int)] = [:]
            var visited: Set<Int> = [start]
            var queue = [start]
            var head = 0
            var found = false
            while head < queue.count && !found {
                let code = queue[head]
                head += 1
                for (index, action) in actions.enumerated() {
                    let next = action[code]
                    if visited.contains(next) { continue }
                    visited.insert(next)
                    parents[next] = (code, index)
                    if next == goal {
                        found = true
                        break
                    }
                    queue.append(next)
                }
            }
            guard found else { throw SolverFailure.stuck("middle edge \(piece)") }
            var path: [Int] = []
            var cursor = goal
            while cursor != start {
                let parent = parents[cursor]!
                path.append(parent.macro)
                cursor = parent.code
            }
            for macro in path.reversed() {
                perform(alphabet[macro])
            }
        }
    }

    // MARK: Stage 4 — top cross (orient top edges)

    private mutating func solveTopCross() throws {
        let alg = [Move](notation: "F R U R' U' F'")!
        var iterations = 0
        while true {
            let good = (0..<4).filter { state.edgeOrientation[$0] == 0 }
            if good.count == 4 { return }
            iterations += 1
            if iterations > 5 { throw SolverFailure.stuck("top cross") }
            if good.count != 2 {
                perform(alg)  // dot case (0 good)
                continue
            }
            let set = Set(good)
            // U slot order: ur 0, uf 1, ul 2, ub 3. U turn moves i → i+1.
            // L case: good pair adjacent → align to {ul, ub}; line: good
            // pair opposite → align to {ur, ul} (horizontal).
            for k in 0..<4 {
                let shifted = Set(good.map { ($0 + k) % 4 })
                if shifted == Set([2, 3]) || shifted == Set([0, 2]) {
                    performU(times: k)
                    perform(alg)
                    break
                }
                if k == 3 {
                    throw SolverFailure.stuck("top cross alignment")
                }
            }
        }
    }

    // MARK: Stage 5 — permute top corners (A-perm, corners only)

    /// Outer-turn A-perm: cycles three top corners, leaves every edge
    /// and the fourth corner alone. The fixed slot is derived from the
    /// cube algebra at startup so the conjugation can't drift.
    private static let aPerm = [Move](notation: "R' F R' B2 R F' R' B2 R2")!

    private static let aPermFixedSlot: Int = {
        let effect = CubeState.solved.applying(aPerm)
        for slot in 0..<4 where effect.cornerPermutation[slot] == slot {
            return slot
        }
        fatalError("A-perm should fix one top corner")
    }()

    private mutating func permuteTopCorners() throws {
        // Re-align U each round so at least one corner is home — the U
        // turn is also what absorbs odd permutation parity, which the
        // 3-cycle algorithm alone can never fix (e.g. two swapped
        // corners). Bounded loop; the test suite sweeps all parities.
        func placedCount(afterUTurns k: Int) -> Int {
            var count = 0
            for slot in 0..<4 where state.cornerPermutation[(slot - k + 4) % 4] == slot {
                count += 1
            }
            return count
        }

        var iterations = 0
        while true {
            // The A-perm only produces even permutations, so the U
            // alignment must make the top-corner permutation even: pick
            // a turn count with the same parity as the permutation.
            let parity = permutationParity(Array(state.cornerPermutation[0..<4]))
            let candidates = parity == 0 ? [0, 2] : [1, 3]
            let bestAlignment = candidates.max {
                placedCount(afterUTurns: $0) < placedCount(afterUTurns: $1)
            }!
            performU(times: bestAlignment)
            let placed = (0..<4).filter { state.cornerPermutation[$0] == $0 }
            if placed.count == 4 { return }
            iterations += 1
            if iterations > 8 { throw SolverFailure.stuck("permute corners") }
            if let anchor = placed.first {
                // Use the variant whose fixed slot is the placed corner.
                perform(Self.rotatedY(Self.aPerm, times: anchor - Self.aPermFixedSlot))
            } else {
                perform(Self.aPerm)
            }
        }
    }

    // MARK: Stage 6 — orient top corners

    private mutating func orientTopCorners() throws {
        let twist = [Move](notation: "R' D' R D R' D' R D")!
        var iterations = 0
        while (0..<4).contains(where: { state.cornerOrientation[$0] != 0 }) {
            iterations += 1
            if iterations > 12 { throw SolverFailure.stuck("orient corners") }
            // Bring an unoriented corner to URF (slot 0) with U turns.
            let target = (0..<4).first { state.cornerOrientation[$0] != 0 }!
            performU(times: -target)
            var twists = 0
            while state.cornerOrientation[0] != 0 {
                perform(twist)
                twists += 1
                if twists > 2 { throw SolverFailure.stuck("corner twist") }
            }
        }
        // The interleaved U turns left the top layer rotated; realign so
        // the (already permuted) corners are home again.
        for k in 0..<4 {
            if (0..<4).allSatisfy({ state.cornerPermutation[$0] == $0 }) { return }
            _ = k
            performU(times: 1)
        }
        guard (0..<4).allSatisfy({ state.cornerPermutation[$0] == $0 }) else {
            throw SolverFailure.stuck("orient realign")
        }
    }

    // MARK: Stage 7 — permute top edges (outer Ua-perm)

    private static let uaPerm = [Move](notation: "R U' R U R U R U' R' U' R2")!

    private mutating func permuteTopEdges() throws {
        var iterations = 0
        while !state.isSolved {
            iterations += 1
            if iterations > 6 { throw SolverFailure.stuck("permute edges") }
            let placed = (0..<4).filter { state.edgePermutation[$0] == $0 }
            if let anchor = placed.first, placed.count == 1 {
                // Conjugate so the solved edge sits at UB (slot 3) while
                // the cycle runs, then restore the frame.
                let k = 3 - anchor
                performU(times: k)
                perform(Self.uaPerm)
                performU(times: -k)
            } else {
                perform(Self.uaPerm)
            }
        }
    }
}
