/// Kociemba's two-phase algorithm.
///
/// Phase 1 searches to the subgroup G1 = ⟨U, D, R2, L2, F2, B2⟩ (all
/// pieces oriented, slice edges in the slice); phase 2 finishes inside
/// G1. The search keeps improving its answer until the time budget runs
/// out, then returns the best solution found (typically ~19–22 moves).
public final class KociembaSolver: Sendable {
    private let tables: SolverTables

    public init(tables: SolverTables) {
        self.tables = tables
    }

    /// Solves the cube, returning a move sequence that brings `state` to
    /// solved, or nil if the state is not a legal cube.
    ///
    /// The search always returns its first solution even if the budget
    /// has expired; the budget caps how long it keeps optimizing.
    public func solve(
        _ state: CubeState,
        maxLength: Int = 24,
        timeBudget: Duration = .milliseconds(120)
    ) -> [Move]? {
        guard state.isLegal else { return nil }
        if state.isSolved { return [] }
        let search = Search(
            tables: tables, state: state, maxLength: maxLength, timeBudget: timeBudget)
        if let solution = search.run() {
            return solution
        }
        // A tight maxLength can (rarely) be unreachable within phase
        // depth limits; retry with the two-phase upper bound.
        guard maxLength < 30 else { return nil }
        return Search(
            tables: tables, state: state, maxLength: 30, timeBudget: timeBudget
        ).run()
    }
}

extension Scrambler {
    /// A move sequence that takes a solved cube to `state` (the inverse
    /// of a solution), suitable for animating a scramble.
    public static func scrambleSequence(
        to state: CubeState, using solver: KociembaSolver
    ) -> [Move]? {
        solver.solve(state)?.inverse
    }
}

extension CubeState {
    /// Whether this state is reachable by face turns from solved: valid
    /// permutations, orientation sums, and matching parity.
    public var isLegal: Bool {
        Set(cornerPermutation) == Set(0..<8)
            && Set(edgePermutation) == Set(0..<12)
            && cornerOrientation.allSatisfy { (0..<3).contains($0) }
            && edgeOrientation.allSatisfy { (0..<2).contains($0) }
            && cornerOrientation.reduce(0, +) % 3 == 0
            && edgeOrientation.reduce(0, +) % 2 == 0
            && permutationParity(cornerPermutation) == permutationParity(edgePermutation)
    }
}

/// One solve. Mutable search state lives here so the solver itself
/// stays Sendable.
private final class Search {
    private let twistMove: [UInt16]
    private let flipMove: [UInt16]
    private let sliceMove: [UInt16]
    private let cornerPermutationMove: [UInt16]
    private let udEdgePermutationMove: [UInt16]
    private let sliceEdgePermutationMove: [UInt16]
    private let prune1SliceFlip: [Int8]
    private let prune1SliceTwist: [Int8]
    private let prune2SliceCorner: [Int8]
    private let prune2SliceEdge: [Int8]

    private let initialState: CubeState
    private let clock = ContinuousClock()
    private let deadline: ContinuousClock.Instant

    private var best: [Move]?
    private var bestLength: Int
    private var path1 = [Int](repeating: 0, count: 16)
    private var path2 = [Int](repeating: 0, count: 20)
    private var nodeCount = 0
    private var aborted = false

    init(tables: SolverTables, state: CubeState, maxLength: Int, timeBudget: Duration) {
        twistMove = tables.twistMove
        flipMove = tables.flipMove
        sliceMove = tables.sliceMove
        cornerPermutationMove = tables.cornerPermutationMove
        udEdgePermutationMove = tables.udEdgePermutationMove
        sliceEdgePermutationMove = tables.sliceEdgePermutationMove
        prune1SliceFlip = tables.prune1SliceFlip
        prune1SliceTwist = tables.prune1SliceTwist
        prune2SliceCorner = tables.prune2SliceCorner
        prune2SliceEdge = tables.prune2SliceEdge
        initialState = state
        bestLength = maxLength + 1
        deadline = clock.now.advanced(by: timeBudget)
    }

    func run() -> [Move]? {
        let twist = Coordinates.twist(of: initialState)
        let flip = Coordinates.flip(of: initialState)
        let slice = Coordinates.slice(of: initialState)
        for depth1 in 0...12 {
            if aborted || bestLength <= depth1 { break }
            phase1(twist: twist, flip: flip, slice: slice,
                   remaining: depth1, depth: 0, lastFace: -1)
        }
        return best
    }

    private func phase1(
        twist: Int, flip: Int, slice: Int, remaining: Int, depth: Int, lastFace: Int
    ) {
        if aborted { return }
        checkDeadline()
        if remaining == 0 {
            guard twist == 0, flip == 0, slice == Coordinates.solvedSlice else { return }
            // If the last move stays inside G1, this maneuver was already
            // tried with a shorter phase 1.
            if depth > 0 && isPhase2Move(path1[depth - 1]) { return }
            startPhase2(depth1: depth, lastFace: lastFace)
            return
        }
        let heuristic = max(
            prune1SliceFlip[slice * Coordinates.flipCount + flip],
            prune1SliceTwist[slice * Coordinates.twistCount + twist]
        )
        if Int(heuristic) > remaining { return }
        for move in 0..<18 {
            let face = move / 3
            guard faceAllowed(face, after: lastFace) else { continue }
            path1[depth] = move
            phase1(
                twist: Int(twistMove[twist * 18 + move]),
                flip: Int(flipMove[flip * 18 + move]),
                slice: Int(sliceMove[slice * 18 + move]),
                remaining: remaining - 1, depth: depth + 1, lastFace: face
            )
            if aborted { return }
        }
    }

    private func startPhase2(depth1: Int, lastFace: Int) {
        var state = initialState
        for i in 0..<depth1 { state.apply(Move(rawValue: path1[i])!) }
        let cornerPerm = Coordinates.cornerPermutation(of: state)
        let udEdgePerm = Coordinates.udEdgePermutation(of: state)
        let slicePerm = Coordinates.sliceEdgePermutation(of: state)
        if cornerPerm == 0 && udEdgePerm == 0 && slicePerm == 0 {
            record(depth1: depth1, depth2: 0)
            return
        }
        let heuristic = Int(max(
            prune2SliceCorner[slicePerm * Coordinates.cornerPermutationCount + cornerPerm],
            prune2SliceEdge[slicePerm * Coordinates.udEdgePermutationCount + udEdgePerm]
        ))
        let maxDepth2 = min(18, bestLength - 1 - depth1)
        guard heuristic <= maxDepth2 else { return }
        for target in heuristic...maxDepth2 {
            let found = phase2(
                cornerPerm: cornerPerm, udEdgePerm: udEdgePerm, slicePerm: slicePerm,
                remaining: target, depth: 0, lastFace: lastFace, depth1: depth1
            )
            if found || aborted { return }
        }
    }

    private func phase2(
        cornerPerm: Int, udEdgePerm: Int, slicePerm: Int,
        remaining: Int, depth: Int, lastFace: Int, depth1: Int
    ) -> Bool {
        if aborted { return false }
        checkDeadline()
        if remaining == 0 {
            guard cornerPerm == 0, udEdgePerm == 0, slicePerm == 0 else { return false }
            record(depth1: depth1, depth2: depth)
            return true
        }
        let heuristic = max(
            prune2SliceCorner[slicePerm * Coordinates.cornerPermutationCount + cornerPerm],
            prune2SliceEdge[slicePerm * Coordinates.udEdgePermutationCount + udEdgePerm]
        )
        if Int(heuristic) > remaining { return false }
        for index in 0..<10 {
            let move = SolverTables.phase2Moves[index]
            let face = move / 3
            guard faceAllowed(face, after: lastFace) else { continue }
            path2[depth] = move
            let found = phase2(
                cornerPerm: Int(cornerPermutationMove[cornerPerm * 10 + index]),
                udEdgePerm: Int(udEdgePermutationMove[udEdgePerm * 10 + index]),
                slicePerm: Int(sliceEdgePermutationMove[slicePerm * 10 + index]),
                remaining: remaining - 1, depth: depth + 1, lastFace: face, depth1: depth1
            )
            if found { return true }
            if aborted { return false }
        }
        return false
    }

    private func record(depth1: Int, depth2: Int) {
        let length = depth1 + depth2
        guard length < bestLength else { return }
        bestLength = length
        best = (0..<depth1).map { Move(rawValue: path1[$0])! }
            + (0..<depth2).map { Move(rawValue: path2[$0])! }
    }

    /// U and D turns and all half turns stay inside G1.
    private func isPhase2Move(_ move: Int) -> Bool {
        move % 3 == 1 || move / 3 == 0 || move / 3 == 3
    }

    /// Never repeat a face; force opposite-face pairs into one canonical
    /// order (U before D, R before L, F before B).
    private func faceAllowed(_ face: Int, after lastFace: Int) -> Bool {
        lastFace < 0 || (face != lastFace && face + 3 != lastFace)
    }

    /// Aborting only once a solution exists keeps the budget soft: the
    /// caller always gets an answer.
    private func checkDeadline() {
        nodeCount += 1
        if nodeCount & 0x3FF == 0, best != nil, clock.now > deadline {
            aborted = true
        }
    }
}
