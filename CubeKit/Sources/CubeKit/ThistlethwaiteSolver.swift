/// The four phases of Thistlethwaite's algorithm, in order. Each phase
/// restricts the move set further and lands the cube in a smaller
/// subgroup, until only half turns remain.
public enum ThistlethwaiteStage: CaseIterable, Sendable, SolverStage {
    case orientEdges
    case orientCornersAndSlice
    case separatePieces
    case finish

    public var displayName: String {
        switch self {
        case .orientEdges: "Orient edges"
        case .orientCornersAndSlice: "Orient corners + slice"
        case .separatePieces: "Separate pieces"
        case .finish: "Half-turn finish"
        }
    }
}

/// Thistlethwaite's 1981 four-phase group reduction: a fixed nesting of
/// move-set restrictions, each phase solved provably shortest from its
/// distance table. Solutions run ~30–45 moves and every phase has a
/// clear goal, which makes the method pleasant to follow.
public struct ThistlethwaiteSolver: Sendable {
    private let tables: ThistlethwaiteTables

    public init(tables: ThistlethwaiteTables) {
        self.tables = tables
    }

    public func solve(_ state: CubeState) -> StagedSolution<ThistlethwaiteStage>? {
        guard state.isLegal else { return nil }
        var current = state
        var stages: [StagedSolution<ThistlethwaiteStage>.Stage] = []
        for (phase, stage) in ThistlethwaiteStage.allCases.enumerated() {
            guard let moves = descend(&current, phase: phase) else {
                assertionFailure("thistlethwaite stuck in phase \(phase + 1)")
                return nil
            }
            stages.append(.init(stage: stage, moves: moves))
        }
        guard current.isSolved else {
            assertionFailure("thistlethwaite end state not solved")
            return nil
        }
        return StagedSolution(stages: stages)
    }

    /// A shorter, still staged, Thistlethwaite variant. It keeps the same
    /// subgroup chain and move restrictions as `solve`, but searches several
    /// phase exits and allows a small amount of phase slack to reduce the
    /// total move count. If the deadline is hit, it returns the best complete
    /// candidate found so far; the classic solution is always used as a
    /// fallback.
    public func solveOptimized(
        _ state: CubeState,
        timeBudget: Duration = .seconds(1)
    ) -> StagedSolution<ThistlethwaiteStage>? {
        solveOptimized(state, config: .default, timeBudget: timeBudget)
    }

    /// Greedy descent over one phase's distance table: from distance d,
    /// some allowed move always reaches d − 1 (the move sets are closed
    /// under inverses, so a BFS parent edge runs backwards from every
    /// state), and any such move lies on a shortest path.
    private func descend(_ state: inout CubeState, phase: Int) -> [Move]? {
        let allowed = ThistlethwaiteTables.phaseMoves[phase].map { Move(rawValue: $0)! }
        guard var distance = tables.distance(of: state, phase: phase) else { return nil }
        var moves: [Move] = []
        while distance > 0 {
            var stepped = false
            for move in allowed {
                let next = state.applying(move)
                if tables.distance(of: next, phase: phase) == distance - 1 {
                    state = next
                    moves.append(move)
                    distance -= 1
                    stepped = true
                    break
                }
            }
            guard stepped else { return nil }
        }
        return moves
    }
}

// MARK: - Optimized search

struct ThistlethwaiteOptimizationConfig: Sendable {
    var beamWidth: Int
    var endpointCap: Int
    var phaseSlack: [Int]

    static let `default` = ThistlethwaiteOptimizationConfig(
        beamWidth: 64,
        endpointCap: 256,
        phaseSlack: [1, 2, 2, 0]
    )
}

extension ThistlethwaiteSolver {
    func solveOptimized(
        _ state: CubeState,
        config: ThistlethwaiteOptimizationConfig,
        timeBudget: Duration
    ) -> StagedSolution<ThistlethwaiteStage>? {
        guard state.isLegal else { return nil }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeBudget)
        func expired() -> Bool { clock.now >= deadline }

        var best: StagedSolution<ThistlethwaiteStage>?
        func consider(_ candidate: StagedSolution<ThistlethwaiteStage>?) {
            guard let candidate else { return }
            let merged = stageBoundaryMerged(candidate)
            assert(stagesAreValid(merged, from: state))
            if isBetter(merged, than: best) {
                best = merged
            }
        }

        // A complete, classic candidate is always available for legal states,
        // so timeout paths never return a partial search result.
        consider(solve(state))
        for policy in GreedyPolicy.allCases where !expired() {
            consider(solveGreedy(state, policy: policy))
        }
        if !expired() {
            consider(solveBeam(state, config: config, expired: expired))
        }
        return best
    }

    private enum GreedyPolicy: CaseIterable {
        case current
        case reversed
        case halfTurnsFirst
        case nextPhaseEntry
    }

    private struct Candidate {
        var state: CubeState
        var stages: [[Move]]
        var score: Int

        var length: Int { stages.reduce(0) { $0 + $1.count } }
        var solution: StagedSolution<ThistlethwaiteStage> {
            StagedSolution(stages: zip(ThistlethwaiteStage.allCases, stages).map {
                .init(stage: $0.0, moves: $0.1)
            })
        }
    }

    private struct PhasePath {
        var state: CubeState
        var moves: [Move]
        var distance: Int
        var lastFace: Int
        var orderBias: Int
    }

    private func solveGreedy(
        _ state: CubeState,
        policy: GreedyPolicy
    ) -> StagedSolution<ThistlethwaiteStage>? {
        var current = state
        var stages: [StagedSolution<ThistlethwaiteStage>.Stage] = []
        for (phase, stage) in ThistlethwaiteStage.allCases.enumerated() {
            guard let moves = descendGreedy(&current, phase: phase, policy: policy) else {
                return nil
            }
            stages.append(.init(stage: stage, moves: moves))
        }
        return current.isSolved ? StagedSolution(stages: stages) : nil
    }

    private func descendGreedy(
        _ state: inout CubeState,
        phase: Int,
        policy: GreedyPolicy
    ) -> [Move]? {
        guard var distance = tables.distance(of: state, phase: phase) else { return nil }
        var moves: [Move] = []
        while distance > 0 {
            let allowed = orderedMoves(phase: phase, policy: policy)
            var choices: [(move: Move, next: CubeState, score: Int)] = []
            for (index, move) in allowed.enumerated() {
                let next = state.applying(move)
                guard tables.distance(of: next, phase: phase) == distance - 1 else { continue }
                choices.append((move, next, greedyScore(
                    next: next, phase: phase, distance: distance, policy: policy, order: index)))
            }
            guard let choice = choices.min(by: {
                $0.score == $1.score ? $0.move.rawValue < $1.move.rawValue : $0.score < $1.score
            }) else { return nil }
            state = choice.next
            moves.append(choice.move)
            distance -= 1
        }
        return moves
    }

    private func greedyScore(
        next: CubeState,
        phase: Int,
        distance: Int,
        policy: GreedyPolicy,
        order: Int
    ) -> Int {
        switch policy {
        case .nextPhaseEntry where distance == 1 && phase < 3:
            return (tables.distance(of: next, phase: phase + 1) ?? 1_000) * 100 + order
        default:
            return order
        }
    }

    private func solveBeam(
        _ state: CubeState,
        config: ThistlethwaiteOptimizationConfig,
        expired: () -> Bool
    ) -> StagedSolution<ThistlethwaiteStage>? {
        var candidates = [Candidate(state: state, stages: [], score: 0)]
        for phase in 0..<4 {
            var nextCandidates: [Candidate] = []
            let endpointLimit = max(1, config.endpointCap / max(candidates.count, 1))
            for candidate in candidates {
                if expired() { break }
                let endpoints = phaseEndpoints(
                    from: candidate.state, phase: phase, config: config,
                    endpointLimit: endpointLimit, expired: expired)
                for endpoint in endpoints {
                    var stages = candidate.stages
                    stages.append(endpoint.moves)
                    var next = Candidate(
                        state: endpoint.state,
                        stages: stages,
                        score: candidate.length + endpoint.moves.count)
                    next.score = score(candidate: next, nextPhase: phase + 1)
                    nextCandidates.append(next)
                }
            }
            if nextCandidates.isEmpty { return nil }
            candidates = prune(nextCandidates, limit: config.endpointCap)
                .prefix(config.beamWidth)
                .map { $0 }
        }

        var best: StagedSolution<ThistlethwaiteStage>?
        for candidate in candidates where candidate.state.isSolved {
            let solution = candidate.solution
            let merged = stageBoundaryMerged(solution)
            if isBetter(merged, than: best.map(stageBoundaryMerged)) {
                best = solution
            }
        }
        return best
    }

    private func phaseEndpoints(
        from state: CubeState,
        phase: Int,
        config: ThistlethwaiteOptimizationConfig,
        endpointLimit: Int,
        expired: () -> Bool
    ) -> [PhasePath] {
        guard let startDistance = tables.distance(of: state, phase: phase) else { return [] }
        let slack = phase < config.phaseSlack.count ? config.phaseSlack[phase] : 0
        let bound = startDistance + slack
        var endpoints: [PhasePath] = []
        var frontier = [PhasePath(
            state: state, moves: [], distance: startDistance, lastFace: -1, orderBias: 0)]

        for depth in 0...bound {
            if expired() { break }
            var nextFrontier: [PhasePath] = []
            for path in frontier {
                if path.distance == 0 {
                    endpoints.append(path)
                    continue
                }
                guard depth < bound else { continue }
                let remainingAfterMove = bound - depth - 1
                for (order, move) in orderedMoves(phase: phase, policy: .halfTurnsFirst).enumerated() {
                    let face = move.face.rawValue
                    guard faceAllowed(face, after: path.lastFace) else { continue }
                    let next = path.state.applying(move)
                    guard let distance = tables.distance(of: next, phase: phase),
                          distance <= remainingAfterMove
                    else { continue }
                    nextFrontier.append(PhasePath(
                        state: next,
                        moves: path.moves + [move],
                        distance: distance,
                        lastFace: face,
                        orderBias: path.orderBias * 31 + order))
                }
            }
            if endpoints.count >= endpointLimit { break }
            frontier = prunePaths(nextFrontier, phase: phase, limit: config.beamWidth)
        }

        return Array(prunePaths(endpoints, phase: phase, limit: endpointLimit)
            .prefix(endpointLimit))
    }

    private func score(candidate: Candidate, nextPhase: Int) -> Int {
        guard nextPhase < 4 else { return candidate.length }
        var current = candidate.state
        var length = candidate.length
        for phase in nextPhase..<4 {
            guard let moves = descendGreedy(&current, phase: phase, policy: .nextPhaseEntry)
            else { return Int.max / 2 }
            length += moves.count
        }
        return length
    }

    private func orderedMoves(phase: Int, policy: GreedyPolicy) -> [Move] {
        let moves = ThistlethwaiteTables.phaseMoves[phase].map { Move(rawValue: $0)! }
        switch policy {
        case .current, .nextPhaseEntry:
            return moves
        case .reversed:
            return moves.reversed()
        case .halfTurnsFirst:
            return moves.enumerated().sorted {
                let lhsHalf = $0.element.quarterTurns == 2
                let rhsHalf = $1.element.quarterTurns == 2
                if lhsHalf != rhsHalf { return lhsHalf }
                return $0.offset < $1.offset
            }.map(\.element)
        }
    }

    private func prune(_ candidates: [Candidate], limit: Int) -> [Candidate] {
        var bestByState: [CubeState: Candidate] = [:]
        for candidate in candidates {
            if let existing = bestByState[candidate.state],
               !candidateSortPrecedes(candidate, existing) {
                continue
            }
            bestByState[candidate.state] = candidate
        }
        return bestByState.values.sorted(by: candidateSortPrecedes).prefix(limit).map { $0 }
    }

    private func prunePaths(_ paths: [PhasePath], phase: Int, limit: Int) -> [PhasePath] {
        var bestByState: [CubeState: PhasePath] = [:]
        for path in paths {
            if let existing = bestByState[path.state], !pathSortPrecedes(path, existing, phase: phase) {
                continue
            }
            bestByState[path.state] = path
        }
        return bestByState.values.sorted { pathSortPrecedes($0, $1, phase: phase) }
            .prefix(limit)
            .map { $0 }
    }

    private func candidateSortPrecedes(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.score != rhs.score { return lhs.score < rhs.score }
        if lhs.length != rhs.length { return lhs.length < rhs.length }
        return lexicographicallyPrecedes(lhs.stages.flatMap { $0 }, rhs.stages.flatMap { $0 })
    }

    private func pathSortPrecedes(_ lhs: PhasePath, _ rhs: PhasePath, phase: Int) -> Bool {
        if lhs.distance != rhs.distance { return lhs.distance < rhs.distance }
        let lhsNext = phase < 3 && lhs.distance == 0
            ? tables.distance(of: lhs.state, phase: phase + 1) ?? 1_000
            : 1_000
        let rhsNext = phase < 3 && rhs.distance == 0
            ? tables.distance(of: rhs.state, phase: phase + 1) ?? 1_000
            : 1_000
        if lhsNext != rhsNext { return lhsNext < rhsNext }
        if lhs.moves.count != rhs.moves.count { return lhs.moves.count < rhs.moves.count }
        if lhs.orderBias != rhs.orderBias { return lhs.orderBias < rhs.orderBias }
        return lexicographicallyPrecedes(lhs.moves, rhs.moves)
    }

    private func isBetter(
        _ lhs: StagedSolution<ThistlethwaiteStage>,
        than rhs: StagedSolution<ThistlethwaiteStage>?
    ) -> Bool {
        guard let rhs else { return true }
        if lhs.moves.count != rhs.moves.count { return lhs.moves.count < rhs.moves.count }
        return lexicographicallyPrecedes(lhs.moves, rhs.moves)
    }

    private func lexicographicallyPrecedes(_ lhs: [Move], _ rhs: [Move]) -> Bool {
        for (a, b) in zip(lhs, rhs) where a.rawValue != b.rawValue {
            return a.rawValue < b.rawValue
        }
        return lhs.count < rhs.count
    }

    /// Never repeat a face; force opposite-face pairs into one canonical order
    /// to keep slack search from spending budget on duplicate commutations.
    private func faceAllowed(_ face: Int, after lastFace: Int) -> Bool {
        lastFace < 0 || (face != lastFace && face + 3 != lastFace)
    }
}

// MARK: - Stage-aware cleanup and validation

extension ThistlethwaiteSolver {
    func stageBoundaryMerged(
        _ solution: StagedSolution<ThistlethwaiteStage>
    ) -> StagedSolution<ThistlethwaiteStage> {
        var stages = solution.stages.map { (stage: $0.stage, moves: $0.moves) }
        var left = 0
        while left < stages.count {
            guard !stages[left].moves.isEmpty else {
                left += 1
                continue
            }
            var right = left + 1
            while right < stages.count, stages[right].moves.isEmpty { right += 1 }
            guard right < stages.count else { break }

            guard let previous = stages[left].moves.last,
                  let next = stages[right].moves.first,
                  previous.face == next.face
            else {
                left = right
                continue
            }

            let turns = (previous.quarterTurns + next.quarterTurns) % 4
            stages[left].moves.removeLast()
            stages[right].moves.removeFirst()
            if turns != 0 {
                stages[left].moves.append(Move(face: previous.face, quarterTurns: turns))
            }
        }

        return StagedSolution(stages: stages.map {
            .init(stage: $0.stage, moves: $0.moves)
        })
    }

    func stagesAreValid(
        _ solution: StagedSolution<ThistlethwaiteStage>,
        from start: CubeState
    ) -> Bool {
        var state = start
        for (phase, stage) in solution.stages.enumerated() {
            let allowed = Set(ThistlethwaiteTables.phaseMoves[phase].map { Move(rawValue: $0)! })
            guard stage.moves.allSatisfy({ allowed.contains($0) }) else { return false }
            state = state.applying(stage.moves)
            guard stageGoalHolds(phase: phase, state: state) else { return false }
        }
        return state.isSolved
    }

    private func stageGoalHolds(phase: Int, state: CubeState) -> Bool {
        var holds = state.edgeOrientation.allSatisfy { $0 == 0 }
        if phase >= 1 {
            holds = holds && state.cornerOrientation.allSatisfy { $0 == 0 }
                && (8..<12).allSatisfy { state.edgePermutation[$0] >= 8 }
        }
        if phase >= 2 {
            holds = holds && [1, 3, 5, 7].allSatisfy {
                [1, 3, 5, 7].contains(state.edgePermutation[$0])
            }
            holds = holds && tables.corner96Index[
                Coordinates.rankPermutation(state.cornerPermutation)] != nil
        }
        if phase >= 3 {
            holds = holds && state.isSolved
        }
        return holds
    }
}
