import Testing
@testable import CubeKit

@Suite struct BeginnerSolverTests {
    private let solver = BeginnerSolver()

    @Test func solvesSolvedCubeWithNoMoves() throws {
        let solution = try #require(solver.solve(.solved))
        #expect(solution.moves.isEmpty)
    }

    @Test func rejectsIllegalState() {
        var state = CubeState.solved
        state.cornerOrientation[0] = 1
        #expect(solver.solve(state) == nil)
    }

    /// The standard insert algorithms must preserve the bottom layer and
    /// the other middle slots — every stage builds on this.
    @Test func insertAlgorithmsPreserveLowerStructure() {
        let right = [Move](notation: "U R U' R' U' F' U F")!
        let left = [Move](notation: "U' F' U F U R U' R'")!
        for alg in [right, left] {
            let state = CubeState.solved.applying(alg)
            // Bottom edges and corners untouched.
            for piece in 4...7 {
                #expect(state.edgePermutation[piece] == piece)
                #expect(state.edgeOrientation[piece] == 0)
                #expect(state.cornerPermutation[piece] == piece)
                #expect(state.cornerOrientation[piece] == 0)
            }
            // Middle slots other than fr (8) untouched.
            for slot in 9...11 {
                #expect(state.edgePermutation[slot] == slot)
                #expect(state.edgeOrientation[slot] == 0)
            }
        }
    }

    /// The A-perm must move corners only; the Ua-perm edges only.
    @Test func permutationAlgorithmsAreClean() {
        let aPerm = CubeState.solved.applying([Move](notation: "R' F R' B2 R F' R' B2 R2")!)
        #expect(aPerm.edgePermutation == Array(0..<12))
        #expect(aPerm.edgeOrientation == Array(repeating: 0, count: 12))
        #expect(aPerm.cornerOrientation == Array(repeating: 0, count: 8))
        for piece in 4...7 {
            #expect(aPerm.cornerPermutation[piece] == piece)
        }
        #expect((0..<4).filter { aPerm.cornerPermutation[$0] == $0 }.count == 1)

        let uaPerm = CubeState.solved.applying([Move](notation: "R U' R U R U R U' R' U' R2")!)
        #expect(uaPerm.cornerPermutation == Array(0..<8))
        #expect(uaPerm.cornerOrientation == Array(repeating: 0, count: 8))
        #expect(uaPerm.edgeOrientation == Array(repeating: 0, count: 12))
        for slot in 4...11 {
            #expect(uaPerm.edgePermutation[slot] == slot)
        }
        #expect((0..<4).filter { uaPerm.edgePermutation[$0] == $0 }.count == 1)
    }

    @Test func solvesRandomStatesWithValidStages() throws {
        var rng = SeededRandom(seed: 4242)
        for iteration in 0..<200 {
            let start = Scrambler.randomState(using: &rng)
            let solution = try #require(
                solver.solve(start), "iteration \(iteration) returned nil")
            #expect(solution.moves.count <= 400, "iteration \(iteration) too long")

            // Replay stage by stage, checking each stage's invariant.
            var state = start
            var completed: Set<BeginnerStage> = []
            for stage in solution.stages {
                state = state.applying(stage.moves)
                completed.insert(stage.stage)
                checkInvariant(stage.stage, state: state, iteration: iteration)
            }
            #expect(completed == Set(BeginnerStage.allCases))
            #expect(state.isSolved, "iteration \(iteration) not solved")
        }
    }

    private func checkInvariant(
        _ stage: BeginnerStage, state: CubeState, iteration: Int,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        func edgesHome(_ range: ClosedRange<Int>) -> Bool {
            range.allSatisfy {
                state.edgePermutation[$0] == $0 && state.edgeOrientation[$0] == 0
            }
        }
        func cornersHome(_ range: ClosedRange<Int>) -> Bool {
            range.allSatisfy {
                state.cornerPermutation[$0] == $0 && state.cornerOrientation[$0] == 0
            }
        }
        let holds: Bool
        switch stage {
        case .bottomCross:
            holds = edgesHome(4...7)
        case .bottomCorners:
            holds = edgesHome(4...7) && cornersHome(4...7)
        case .middleEdges:
            holds = edgesHome(4...11) && cornersHome(4...7)
        case .topCross:
            holds = edgesHome(4...11) && cornersHome(4...7)
                && (0..<4).allSatisfy { state.edgeOrientation[$0] == 0 }
        case .permuteCorners:
            holds = edgesHome(4...11) && cornersHome(4...7)
                && (0..<4).allSatisfy { state.edgeOrientation[$0] == 0 }
                && (0..<4).allSatisfy { state.cornerPermutation[$0] == $0 }
        case .orientCorners:
            holds = edgesHome(4...11)
                && (0..<8).allSatisfy { state.cornerPermutation[$0] == $0 }
                && state.cornerOrientation == Array(repeating: 0, count: 8)
                && (0..<4).allSatisfy { state.edgeOrientation[$0] == 0 }
        case .permuteEdges:
            holds = state.isSolved
        }
        #expect(holds, "stage \(stage) invariant failed at iteration \(iteration)",
                sourceLocation: sourceLocation)
    }

    @Test func averageLengthIsReasonable() throws {
        var rng = SeededRandom(seed: 77)
        var total = 0
        for _ in 0..<40 {
            let solution = try #require(solver.solve(Scrambler.randomState(using: &rng)))
            total += solution.moves.count
        }
        let average = Double(total) / 40
        #expect(average < 300, "average beginner solution length \(average)")
    }
}
