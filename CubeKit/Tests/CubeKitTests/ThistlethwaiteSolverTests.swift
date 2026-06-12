import Foundation
import Testing
@testable import CubeKit

@Suite struct ThistlethwaiteSolverTests {
    private var solver: ThistlethwaiteSolver {
        ThistlethwaiteSolver(tables: TestTables.thistlethwaite)
    }
    private static let fastTestConfig = ThistlethwaiteOptimizationConfig(
        beamWidth: 8, endpointCap: 24, phaseSlack: [0, 1, 1, 0])
    private static var longSolverTestsEnabled: Bool {
        ProcessInfo.processInfo.environment["CUBEKIT_LONG_SOLVER_TESTS"] == "1"
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
            #expect(solution.moves.count <= 45, "iteration \(iteration) too long")

            checkSolution(solution, from: start, iteration: iteration)
        }
    }

    @Test func optimizedSolvedCubeMatchesClassicShape() throws {
        let solution = try #require(solver.solveOptimized(.solved))
        #expect(solution.stages.count == 4)
        #expect(solution.stages.allSatisfy { $0.moves.isEmpty })
    }

    @Test func optimizedRejectsIllegalState() {
        var state = CubeState.solved
        state.cornerOrientation[0] = 1
        #expect(solver.solveOptimized(state) == nil)
    }

    @Test func optimizedSolvesRandomStatesWithValidStages() throws {
        var rng = SeededRandom(seed: 1982)
        for iteration in 0..<40 {
            let start = Scrambler.randomState(using: &rng)
            let solution = try #require(
                solver.solveOptimized(
                    start, config: Self.fastTestConfig, timeBudget: .milliseconds(120)),
                "iteration \(iteration) returned nil")
            #expect(solution.stages.count == 4)
            checkSolution(solution, from: start, iteration: iteration)
            checkNoMergeableBoundary(solution, iteration: iteration)
        }
    }

    @Test func optimizedIsNoLongerThanClassicBoundaryMergedOnSeededCorpus() throws {
        var rng = SeededRandom(seed: 2718)
        for iteration in 0..<40 {
            let start = Scrambler.randomState(using: &rng)
            let classic = try #require(solver.solve(start))
            let classicMerged = solver.stageBoundaryMerged(classic)
            let optimized = try #require(
                solver.solveOptimized(
                    start, config: Self.fastTestConfig, timeBudget: .milliseconds(120)))
            #expect(
                optimized.moves.count <= classicMerged.moves.count,
                "iteration \(iteration): optimized \(optimized.moves.count) > classic \(classicMerged.moves.count)")
        }
    }

#if !DEBUG
    @Test func optimizedLengthDistributionIsHighTwentiesOnSeededCorpus() throws {
        var rng = SeededRandom(seed: 0xC0DE)
        var lengths: [Int] = []
        for _ in 0..<40 {
            let solution = try #require(
                solver.solveOptimized(Scrambler.randomState(using: &rng), timeBudget: .milliseconds(600)))
            lengths.append(solution.moves.count)
        }
        lengths.sort()
        let median = lengths[lengths.count / 2]
        let p90 = lengths[lengths.count * 90 / 100]
        #expect(
            median <= 27,
            "optimized median \(median), p90 \(p90); lengths \(lengths)")
    }

    @Test func optimizedLongCorrectnessCorpusWhenEnabled() throws {
        guard Self.longSolverTestsEnabled else { return }

        var rng = SeededRandom(seed: 0x500)
        for iteration in 0..<500 {
            let start = Scrambler.randomState(using: &rng)
            let solution = try #require(
                solver.solveOptimized(start, timeBudget: .seconds(1)),
                "iteration \(iteration) returned nil")
            checkSolution(solution, from: start, iteration: iteration)
            checkNoMergeableBoundary(solution, iteration: iteration)
        }
    }

    @Test func optimizedLongReleaseBenchmarkWhenEnabled() throws {
        guard Self.longSolverTestsEnabled else { return }

        var rng = SeededRandom(seed: 0x1_000)
        var lengths: [Int] = []
        var milliseconds: [Double] = []
        for iteration in 0..<1000 {
            let start = Scrambler.randomState(using: &rng)
            let begin = Date()
            let solution = try #require(
                solver.solveOptimized(start, timeBudget: .seconds(1)),
                "iteration \(iteration) returned nil")
            milliseconds.append(Date().timeIntervalSince(begin) * 1000)
            lengths.append(solution.moves.count)
        }

        let sortedLengths = lengths.sorted()
        let sortedTimes = milliseconds.sorted()
        let average = Double(lengths.reduce(0, +)) / Double(lengths.count)
        let median = Self.percentile(sortedLengths, 50)
        let p90 = Self.percentile(sortedLengths, 90)
        let p95 = Self.percentile(sortedLengths, 95)
        let p95Milliseconds = Self.percentile(sortedTimes, 95)
        let maximum = sortedLengths.last ?? 0
        #expect(
            median <= 27,
            "avg \(average), median \(median), p90 \(p90), p95 \(p95), max \(maximum)")
        #expect(
            p95Milliseconds <= 1000,
            "p95 solve time \(p95Milliseconds) ms; times \(sortedTimes)")
    }
#endif

    @Test func stageBoundaryMergePreservesStageInvariants() throws {
        let solutionMoves = [Move](notation: "F U F B R' F R F2 D' R B2 U B2 L L2 U R2 U B2 U2 L2 U' L2 D U2 R2 U2 R2 L2 F2 U2 R2 B2 U2 L2")!
        let start = CubeState.solved.applying(solutionMoves.inverse)
        let solution = try #require(solver.solve(start))
        let merged = solver.stageBoundaryMerged(solution)
        #expect(merged.moves.count <= solution.moves.count)
        checkSolution(merged, from: start, iteration: 0)
        checkNoMergeableBoundary(merged, iteration: 0)
    }

    @Test func tableReachabilityMatchesExpectedPhaseSpaces() {
        let tables = TestTables.thistlethwaite
        #expect(!tables.phase1.contains(-1))
        #expect(!tables.phase2.contains(-1))
        #expect(!tables.phase3.contains(-1))
        #expect(tables.phase4.lazy.filter { $0 >= 0 }.count == ThistlethwaiteTables.phase4Count / 2)
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

    private func checkSolution(
        _ solution: StagedSolution<ThistlethwaiteStage>,
        from start: CubeState,
        iteration: Int,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        var state = start
        for (phase, stage) in solution.stages.enumerated() {
            #expect(
                stage.moves.allSatisfy { Self.phaseMoves[phase].contains($0) },
                "phase \(phase + 1) used a forbidden move at iteration \(iteration)",
                sourceLocation: sourceLocation)
            state = state.applying(stage.moves)
            checkInvariant(
                phase: phase, state: state, iteration: iteration,
                sourceLocation: sourceLocation)
        }
        #expect(state.isSolved, "iteration \(iteration) not solved", sourceLocation: sourceLocation)
    }

    private func checkNoMergeableBoundary(
        _ solution: StagedSolution<ThistlethwaiteStage>,
        iteration: Int,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        var previous: Move?
        for stage in solution.stages where !stage.moves.isEmpty {
            if let previous, let first = stage.moves.first {
                #expect(
                    previous.face != first.face,
                    "mergeable boundary before \(stage.stage.displayName) at iteration \(iteration)",
                    sourceLocation: sourceLocation)
            }
            previous = stage.moves.last
        }
    }

    private static func percentile(_ sorted: [Int], _ percentile: Int) -> Int {
        sorted[min(sorted.count - 1, sorted.count * percentile / 100)]
    }

    private static func percentile(_ sorted: [Double], _ percentile: Int) -> Double {
        sorted[min(sorted.count - 1, sorted.count * percentile / 100)]
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
