import Foundation
import Testing
@testable import CubeKit

/// A small-tier database set: corners + two 4-edge tables. Weak (so
/// tests stay tiny) but admissible — searches are exact, just slower.
private enum TestOptimal {
    static let databases: PatternDatabaseSet = {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CubeKitTestPDB")
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let specs = [
            PDBSpec(kind: .corners, fileName: "optimal-corners.pdb"),
            PDBSpec(kind: .edges([0, 1, 2, 3]), fileName: "test-edges-4.pdb"),
            PDBSpec(kind: .edges([8, 9, 10, 11]), fileName: "test-edges-b4.pdb"),
        ]
        for spec in specs {
            let url = directory.appendingPathComponent(spec.fileName)
            if !FileManager.default.fileExists(atPath: url.path) {
                try! PatternDatabaseSet.generateTable(
                    spec: spec, to: url, report: { _, _ in }, isCancelled: { false })
            }
        }
        let tables = specs.map { try! PatternDatabase(spec: $0, directory: directory) }
        return PatternDatabaseSet(tables: tables, tier: .sevenEdge)
    }()

    static let solver = OptimalSolver(
        databases: databases, upperBoundSolver: TestTables.solver)

    static let solverWithoutUpperBound = OptimalSolver(
        databases: databases, upperBoundSolver: nil)
}

/// Reference: plain exhaustive IDA* with h = 0 — slow but undeniably
/// optimal, for cross-checking lengths on short scrambles.
private func referenceOptimalLength(_ state: CubeState, limit: Int = 8) -> Int? {
    if state.isSolved { return 0 }
    for bound in 1...limit {
        var found = false
        func dfs(_ cube: CubeState, _ g: Int, _ lastFace: Int) {
            if found { return }
            if g == bound {
                found = cube.isSolved
                return
            }
            for move in Move.allCases {
                let face = move.face.rawValue
                guard SearchEngine.faceAllowed(face, after: lastFace) else { continue }
                dfs(cube.applying(move), g + 1, face)
                if found { return }
            }
        }
        dfs(state, 0, -1)
        if found { return bound }
    }
    return nil
}

@Suite struct OptimalSolverTests {
    @Test func fastCubeMatchesCubeState() {
        var rng = SeededRandom(seed: 71)
        for _ in 0..<30 {
            let state = Scrambler.randomState(using: &rng)
            var fast = FastCube(state)
            var slow = state
            for _ in 0..<15 {
                let move = Move.allCases.randomElement(using: &rng)!
                fast = fast.applying(move.rawValue)
                slow = slow.applying(move)
                let reference = FastCube(slow)
                #expect(fast.cornerPermutation == reference.cornerPermutation)
                #expect(fast.cornerOrientation == reference.cornerOrientation)
                #expect(fast.edgePermutation == reference.edgePermutation)
                #expect(fast.edgeOrientation == reference.edgeOrientation)
            }
            #expect(FastCube(slow).isSolved == slow.isSolved)
        }
    }

    @Test func engineHeuristicMatchesDatabaseSet() {
        let engine = SearchEngine(databases: TestOptimal.databases)
        var rng = SeededRandom(seed: 72)
        for _ in 0..<100 {
            let state = Scrambler.randomState(using: &rng)
            #expect(engine.heuristic(of: FastCube(state))
                == TestOptimal.databases.heuristic(for: state))
        }
    }

    @Test func solvedCubeIsTrivial() {
        #expect(TestOptimal.solver.solve(.solved) == [])
    }

    @Test func matchesReferenceOptimalOnShortScrambles() throws {
        var rng = SeededRandom(seed: 73)
        for length in 1...6 {
            for _ in 0..<4 {
                let scramble = (0..<length).map { _ in
                    Move.allCases.randomElement(using: &rng)!
                }
                let state = CubeState.solved.applying(scramble)
                if state.isSolved { continue }
                let expected = try #require(referenceOptimalLength(state))
                let solution = try #require(TestOptimal.solver.solve(state))
                #expect(solution.count == expected,
                        "scramble \(scramble.notation): got \(solution.count), optimal \(expected)")
                #expect(state.applying(solution).isSolved)
            }
        }
    }

    @Test func solvesWithoutUpperBoundSolver() throws {
        var rng = SeededRandom(seed: 74)
        let scramble = (0..<7).map { _ in Move.allCases.randomElement(using: &rng)! }
        let state = CubeState.solved.applying(scramble)
        let solution = try #require(TestOptimal.solverWithoutUpperBound.solve(state))
        #expect(solution.count <= 7)
        #expect(state.applying(solution).isSolved)
    }

    @Test func neverLongerThanTwoPhase() throws {
        // Medium scrambles: weak test-tier heuristics make full random
        // states too slow here; 10-move scrambles stay comfortable.
        var rng = SeededRandom(seed: 75)
        for _ in 0..<3 {
            let scramble = (0..<10).map { _ in Move.allCases.randomElement(using: &rng)! }
            let state = CubeState.solved.applying(scramble)
            let twoPhase = try #require(TestTables.solver.solve(state))
            let optimal = try #require(TestOptimal.solver.solve(state))
            #expect(optimal.count <= twoPhase.count)
            #expect(state.applying(optimal).isSolved)
        }
    }

    @Test func cancellationReturnsNil() {
        var rng = SeededRandom(seed: 76)
        let state = Scrambler.randomState(using: &rng)
        let result = TestOptimal.solver.solve(state, isCancelled: { true })
        #expect(result == nil)
    }

    @Test func reportsProgress() throws {
        var rng = SeededRandom(seed: 77)
        let scramble = (0..<8).map { _ in Move.allCases.randomElement(using: &rng)! }
        let state = CubeState.solved.applying(scramble)
        let progressed = SharedFlag()
        let solution = TestOptimal.solver.solve(state, progress: { progress in
            if progress.currentBound > 0 { progressed.set() }
        })
        #expect(solution != nil)
        #expect(progressed.isSet)
    }
}
