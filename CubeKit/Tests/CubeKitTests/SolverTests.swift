import Testing
@testable import CubeKit

@Suite struct SolverTests {
    @Test func solvedCubeNeedsNoMoves() {
        #expect(TestTables.solver.solve(.solved) == [])
    }

    @Test func illegalStateReturnsNil() {
        var state = CubeState.solved
        state.cornerOrientation[0] = 1
        #expect(TestTables.solver.solve(state) == nil)
    }

    @Test(arguments: Move.allCases)
    func singleMoveScramblesSolveInOneMove(move: Move) {
        let state = CubeState.solved.applying(move)
        let solution = try! #require(TestTables.solver.solve(state))
        #expect(solution.count == 1)
        #expect(state.applying(solution).isSolved)
    }

    @Test func solvesRandomStates() throws {
        let solver = TestTables.solver
        var rng = SeededRandom(seed: 2026)
        var totalLength = 0
        let count = 100
        for _ in 0..<count {
            let state = Scrambler.randomState(using: &rng)
            let solution = try #require(solver.solve(state))
            #expect(state.applying(solution).isSolved)
            #expect(solution.count <= 24)
            totalLength += solution.count
        }
        // Two-phase with a modest budget averages ~19-22 moves.
        #expect(Double(totalLength) / Double(count) <= 22.5)
    }

    @Test func solvesSuperflip() throws {
        let superflip = [Move](notation: "U R2 F B R B2 R U2 L B2 R U' D' R2 F R' L B2 U2 F2")!
        let state = CubeState.solved.applying(superflip)
        let solution = try #require(TestTables.solver.solve(state))
        #expect(state.applying(solution).isSolved)
        #expect(solution.count <= 24)
    }

    @Test func solutionsHaveNoRedundantAdjacentMoves() throws {
        var rng = SeededRandom(seed: 77)
        for _ in 0..<30 {
            let state = Scrambler.randomState(using: &rng)
            let solution = try #require(TestTables.solver.solve(state))
            for i in 1..<solution.count {
                let previous = solution[i - 1].face
                let current = solution[i].face
                #expect(current != previous)
                // Opposite faces only in canonical order (U D fine, D U not).
                if current.rawValue + 3 == previous.rawValue {
                    Issue.record("non-canonical pair \(previous)\(current) in \(solution.notation)")
                }
            }
        }
    }

    @Test func scrambleSequenceReproducesState() throws {
        var rng = SeededRandom(seed: 31)
        for _ in 0..<20 {
            let state = Scrambler.randomState(using: &rng)
            let scramble = try #require(
                Scrambler.scrambleSequence(to: state, using: TestTables.solver))
            #expect(CubeState.solved.applying(scramble) == state)
        }
    }

    @Test func respectsTimeBudgetOrder() throws {
        // A longer budget must never produce a longer solution for the
        // same state (it only keeps improving).
        var rng = SeededRandom(seed: 8)
        let state = Scrambler.randomState(using: &rng)
        let quick = try #require(
            TestTables.solver.solve(state, timeBudget: .milliseconds(5)))
        let thorough = try #require(
            TestTables.solver.solve(state, timeBudget: .milliseconds(400)))
        #expect(thorough.count <= quick.count)
        #expect(state.applying(quick).isSolved)
        #expect(state.applying(thorough).isSolved)
    }
}
