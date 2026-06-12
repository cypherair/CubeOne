import Foundation
import Testing
@testable import CubeKit

@Suite struct CFOPSolverTests {
    private let solver = CFOPSolver()

    // MARK: Extended notation anchors

    /// M2 U M2 U2 M2 U M2 is the H perm: opposite last-layer edges
    /// swap, everything else stays — a strong anchor for the slice
    /// expansion and frame-tracking in the parser.
    @Test func parserExpandsSlicesCorrectly() throws {
        let moves = try #require(ExtendedNotation.moves("M2 U M2 U2 M2 U M2"))
        let state = CubeState.solved.applying(moves)
        #expect(state.cornerPermutation == Array(0..<8))
        #expect(state.cornerOrientation == Array(repeating: 0, count: 8))
        #expect(state.edgeOrientation == Array(repeating: 0, count: 12))
        // ur↔ul, uf↔ub, rest home.
        #expect(state.edgePermutation == [2, 3, 0, 1] + Array(4..<12))
    }

    /// Plain notation passes through unchanged; rotations remap the
    /// letters that follow them.
    @Test func parserHandlesRotations() throws {
        #expect(ExtendedNotation.moves("R U R'") == [Move](notation: "R U R'"))
        // After y the algorithm letter R refers to the absolute B face.
        #expect(ExtendedNotation.moves("y R y'") == [Move.b])
        // x and z tilt the U axis: a net tilt is rejected, net y is fine.
        #expect(ExtendedNotation.moves("x R") == nil)
        #expect(ExtendedNotation.moves("y U") != nil)
        // A wide turn is the opposite face plus a rotation: r ≙ L + x.
        let wide = try #require(ExtendedNotation.moves("r U r'"))
        let direct = try #require(ExtendedNotation.moves("L x U x' L'"))
        #expect(CubeState.solved.applying(wide) == CubeState.solved.applying(direct))
    }

    // MARK: Algorithm table validation

    /// Parse, F2L preservation, case uniqueness, and exhaustive
    /// coverage of all 216 orientation and 288 permutation states of
    /// the last layer — every entry of the 57+21 tables is checked.
    @Test func algorithmTablesAreValid() {
        let issues = CFOPAlgorithms.validationIssues()
        #expect(issues.isEmpty, "\(issues.joined(separator: "\n"))")
    }

    /// By construction: each OLL algorithm, applied to the case its
    /// own inverse builds (under a random pre-rotation), must orient
    /// the last layer — and recognition must pick exactly that entry.
    @Test func everyOLLCaseSolvesByConstruction() throws {
        var rng = SeededRandom(seed: 57)
        for entry in CFOPAlgorithms.ollEntries {
            let moves = try #require(ExtendedNotation.moves(entry.notation))
            let preState = CubeState.solved.applying(moves.inverse)
            let turns = Int.random(in: 0..<4, using: &rng)
            let shifted = preState.applying(
                turns > 0 ? [Move(face: .up, quarterTurns: turns)] : [])
            let solution = try #require(
                solver.solve(shifted), "OLL \(entry.name) returned nil")
            let ollStages = solution.stages.filter {
                if case .oll = $0.stage { return true }
                return false
            }
            #expect(ollStages.count == 1, "OLL \(entry.name): expected one OLL stage")
            if case .oll(let recognized) = ollStages.first?.stage {
                #expect(recognized == entry.name,
                        "OLL \(entry.name) recognized as \(recognized)")
            }
            #expect(shifted.applying(solution.moves).isSolved)
        }
    }

    /// Each PLL algorithm's own case (under random pre- and post-AUF)
    /// must be recognized by name and solved.
    @Test func everyPLLCaseSolvesByConstruction() throws {
        var rng = SeededRandom(seed: 21)
        for entry in CFOPAlgorithms.pllEntries {
            let moves = try #require(ExtendedNotation.moves(entry.notation))
            var preState = CubeState.solved.applying(moves.inverse)
            let turns = Int.random(in: 0..<4, using: &rng)
            if turns > 0 {
                preState = preState.applying([Move(face: .up, quarterTurns: turns)])
            }
            let solution = try #require(
                solver.solve(preState), "PLL \(entry.name) returned nil")
            let pllStages = solution.stages.filter {
                if case .pll = $0.stage { return true }
                return false
            }
            #expect(pllStages.count == 1, "PLL \(entry.name): expected one PLL stage")
            if case .pll(let recognized) = pllStages.first?.stage {
                #expect(recognized == entry.name,
                        "PLL \(entry.name) recognized as \(recognized)")
            }
            #expect(preState.applying(solution.moves).isSolved)
        }
    }

    // MARK: Solver behavior

    @Test func solvesSolvedCubeWithNoMoves() throws {
        let solution = try #require(solver.solve(.solved))
        #expect(solution.moves.isEmpty)
    }

    @Test func rejectsIllegalState() {
        var state = CubeState.solved
        state.cornerOrientation[0] = 1
        #expect(solver.solve(state) == nil)
    }

    @Test func solvesRandomStatesWithValidStages() throws {
        var rng = SeededRandom(seed: 2025)
        for iteration in 0..<200 {
            let start = Scrambler.randomState(using: &rng)
            let solution = try #require(
                solver.solve(start), "iteration \(iteration) returned nil")

            var state = start
            var crossDone = false
            var solvedPairs: Set<Int> = []
            var ollDone = false
            for stage in solution.stages {
                state = state.applying(stage.moves)
                switch stage.stage {
                case .cross:
                    #expect(!crossDone, "duplicate cross stage at iteration \(iteration)")
                    crossDone = true
                case .f2lPair(let slot):
                    #expect(solvedPairs.insert(slot).inserted,
                            "pair \(slot) solved twice at iteration \(iteration)")
                case .oll:
                    #expect(!ollDone, "duplicate OLL stage at iteration \(iteration)")
                    ollDone = true
                case .pll:
                    break
                }
                checkInvariant(
                    state: state, solvedPairs: solvedPairs, crossDone: crossDone,
                    ollDone: ollDone, iteration: iteration)
            }
            #expect(state.isSolved, "iteration \(iteration) not solved")

            // The cross stage is table-optimal: never longer than 8.
            if let cross = solution.stages.first(where: { $0.stage == .cross }) {
                #expect(cross.moves.count <= 8)
            }
        }
    }

    private func checkInvariant(
        state: CubeState, solvedPairs: Set<Int>, crossDone: Bool, ollDone: Bool,
        iteration: Int, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        var holds = true
        if crossDone {
            holds = holds && (4..<8).allSatisfy {
                state.edgePermutation[$0] == $0 && state.edgeOrientation[$0] == 0
            }
        }
        for slot in solvedPairs {
            let corner = 3 + slot  // slot is 1-based
            let edge = 7 + slot
            holds = holds && state.cornerPermutation[corner] == corner
                && state.cornerOrientation[corner] == 0
                && state.edgePermutation[edge] == edge
                && state.edgeOrientation[edge] == 0
        }
        if ollDone {
            holds = holds && (0..<4).allSatisfy {
                state.cornerOrientation[$0] == 0 && state.edgeOrientation[$0] == 0
            }
        }
        #expect(holds, "stage invariant failed at iteration \(iteration)",
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
        // Measured 60.6 over this seed at the time of writing.
        #expect(average <= 70, "average CFOP solution length \(average)")
    }
}
