import Foundation
import Testing
@testable import CubeKit

@Suite struct ThistlethwaiteSolverTests {
    private var solver: ThistlethwaiteSolver {
        ThistlethwaiteSolver(tables: TestTables.thistlethwaite)
    }

    /// Moves each phase may use, written out independently of the
    /// solver's own tables.
    private static let phaseMoves: [Set<Move>] = [
        Set(Move.allCases),
        Set([Move](notation: "U U2 U' D D2 D' L L2 L' R R2 R' F2 B2")!),
        Set([Move](notation: "U U2 U' D D2 D' R2 L2 F2 B2")!),
        Set([Move](notation: "U2 D2 R2 L2 F2 B2")!),
    ]

    /// The corner permutations reachable by half turns alone, built here
    /// by direct closure so the solver's own 96-set isn't trusted.
    private static let squareGroupCornerPermutations: Set<[Int]> = {
        let generators = [Move.u2, .d2, .r2, .l2, .f2, .b2].map {
            CubeState.solved.applying($0).cornerPermutation
        }
        var visited: Set<[Int]> = [Array(0..<8)]
        var queue: [[Int]] = [Array(0..<8)]
        var head = 0
        while head < queue.count {
            let permutation = queue[head]
            head += 1
            for generator in generators {
                let next = (0..<8).map { permutation[generator[$0]] }
                if visited.insert(next).inserted { queue.append(next) }
            }
        }
        return visited
    }()

    @Test func squareGroupClosureHas96CornerPermutations() {
        #expect(Self.squareGroupCornerPermutations.count == 96)
    }

    @Test func solvesSolvedCubeWithFourEmptyStages() throws {
        let solution = try #require(solver.solve(.solved))
        #expect(solution.stages.count == 4)
        #expect(solution.stages.allSatisfy { $0.moves.isEmpty })
    }

    @Test func rejectsIllegalState() {
        var state = CubeState.solved
        state.cornerOrientation[0] = 1
        #expect(solver.solve(state) == nil)
    }

    /// The known per-phase worst cases: 7, 10, 13, 15 (total 45). These
    /// pin the coordinate conventions — any drift in the tables shows up
    /// here first.
    @Test func tableDepthsMatchKnownBounds() {
        let tables = TestTables.thistlethwaite
        #expect(tables.phase1.max() == 7)
        #expect(tables.phase2.max() == 10)
        #expect(tables.phase3.max() == 13)
        #expect(tables.phase4.max() == 15)
    }

    @Test func solvesRandomStatesWithValidStages() throws {
        var rng = SeededRandom(seed: 1981)
        for iteration in 0..<200 {
            let start = Scrambler.randomState(using: &rng)
            let solution = try #require(
                solver.solve(start), "iteration \(iteration) returned nil")
            #expect(solution.stages.count == 4)
            #expect(solution.moves.count <= 52, "iteration \(iteration) too long")

            var state = start
            for (phase, stage) in solution.stages.enumerated() {
                #expect(
                    stage.moves.allSatisfy { Self.phaseMoves[phase].contains($0) },
                    "phase \(phase + 1) used a forbidden move at iteration \(iteration)")
                state = state.applying(stage.moves)
                checkInvariant(phase: phase, state: state, iteration: iteration)
            }
            #expect(state.isSolved, "iteration \(iteration) not solved")
        }
    }

    private func checkInvariant(
        phase: Int, state: CubeState, iteration: Int,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        var holds = state.edgeOrientation.allSatisfy { $0 == 0 }
        if phase >= 1 {
            holds = holds && state.cornerOrientation.allSatisfy { $0 == 0 }
                && (8..<12).allSatisfy { state.edgePermutation[$0] >= 8 }
        }
        if phase >= 2 {
            holds = holds && [1, 3, 5, 7].allSatisfy { [1, 3, 5, 7].contains(state.edgePermutation[$0]) }
                && Self.squareGroupCornerPermutations.contains(state.cornerPermutation)
        }
        if phase >= 3 {
            holds = holds && state.isSolved
        }
        #expect(
            holds, "phase \(phase + 1) invariant failed at iteration \(iteration)",
            sourceLocation: sourceLocation)
    }

    @Test func cachedTablesMatchGenerated() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CubeKitThistlethwaiteRoundTrip-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let generated = TestTables.thistlethwaite
        // First call writes the cache, second one must load it.
        let written = try ThistlethwaiteTables.cached(in: directory)
        let reloaded = try ThistlethwaiteTables.cached(in: directory)
        for tables in [written, reloaded] {
            #expect(tables.phase1 == generated.phase1)
            #expect(tables.phase2 == generated.phase2)
            #expect(tables.phase3 == generated.phase3)
            #expect(tables.phase4 == generated.phase4)
            #expect(tables.corner96Index == generated.corner96Index)
        }
    }
}
