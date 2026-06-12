/// A named phase of a multi-stage solving method.
public protocol SolverStage: Hashable, Sendable {
    var displayName: String { get }
}

/// A solution annotated with the method stage each move belongs to.
public struct StagedSolution<StageKind: SolverStage>: Sendable {
    public struct Stage: Sendable {
        public let stage: StageKind
        public let moves: [Move]

        public init(stage: StageKind, moves: [Move]) {
            self.stage = stage
            self.moves = moves
        }
    }

    public let stages: [Stage]

    public init(stages: [Stage]) {
        self.stages = stages
    }

    public var moves: [Move] { stages.flatMap(\.moves) }
}
