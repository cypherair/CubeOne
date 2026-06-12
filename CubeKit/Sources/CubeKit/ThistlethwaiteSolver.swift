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
