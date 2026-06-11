import Foundation
import Testing
@testable import CubeKit

@Suite struct CoordinateTests {
    @Test func solvedCoordinatesAreCanonical() {
        let solved = CubeState.solved
        #expect(Coordinates.twist(of: solved) == 0)
        #expect(Coordinates.flip(of: solved) == 0)
        #expect(Coordinates.slice(of: solved) == Coordinates.solvedSlice)
        #expect(Coordinates.cornerPermutation(of: solved) == 0)
        #expect(Coordinates.udEdgePermutation(of: solved) == 0)
        #expect(Coordinates.sliceEdgePermutation(of: solved) == 0)
    }

    @Test func permutationRankRoundTrips() {
        for rank in 0..<24 {
            #expect(Coordinates.rankPermutation(
                Coordinates.unrankPermutation(rank, count: 4)) == rank)
        }
        var rng = SeededRandom(seed: 3)
        for _ in 0..<500 {
            let rank = Int.random(in: 0..<40320, using: &rng)
            #expect(Coordinates.rankPermutation(
                Coordinates.unrankPermutation(rank, count: 8)) == rank)
        }
    }

    @Test func sliceRankRoundTrips() {
        for rank in 0..<Coordinates.sliceCount {
            let positions = Coordinates.slicePositions(forSlice: rank)
            #expect(positions == positions.sorted())
            var state = CubeState.solved
            var nextSlice = 8
            var nextOther = 0
            for slot in 0..<12 {
                if positions.contains(slot) {
                    state.edgePermutation[slot] = nextSlice
                    nextSlice += 1
                } else {
                    state.edgePermutation[slot] = nextOther
                    nextOther += 1
                }
            }
            #expect(Coordinates.slice(of: state) == rank)
        }
    }

    @Test func orientationCoordinatesRoundTrip() {
        for twist in stride(from: 0, to: Coordinates.twistCount, by: 17) {
            var state = CubeState.solved
            state.cornerOrientation = Coordinates.cornerOrientations(forTwist: twist)
            #expect(Coordinates.twist(of: state) == twist)
            #expect(state.cornerOrientation.reduce(0, +) % 3 == 0)
        }
        for flip in stride(from: 0, to: Coordinates.flipCount, by: 13) {
            var state = CubeState.solved
            state.edgeOrientation = Coordinates.edgeOrientations(forFlip: flip)
            #expect(Coordinates.flip(of: state) == flip)
            #expect(state.edgeOrientation.reduce(0, +) % 2 == 0)
        }
    }
}

@Suite struct MoveTableTests {
    @Test func phase1TablesMatchCubieGroundTruth() {
        let tables = TestTables.shared
        var rng = SeededRandom(seed: 21)
        for _ in 0..<50 {
            let state = Scrambler.randomState(using: &rng)
            let twist = Coordinates.twist(of: state)
            let flip = Coordinates.flip(of: state)
            let slice = Coordinates.slice(of: state)
            for move in Move.allCases {
                let moved = state.applying(move)
                let m = move.rawValue
                #expect(Int(tables.twistMove[twist * 18 + m]) == Coordinates.twist(of: moved))
                #expect(Int(tables.flipMove[flip * 18 + m]) == Coordinates.flip(of: moved))
                #expect(Int(tables.sliceMove[slice * 18 + m]) == Coordinates.slice(of: moved))
            }
        }
    }

    @Test func phase2TablesMatchCubieGroundTruth() {
        let tables = TestTables.shared
        var rng = SeededRandom(seed: 22)
        for _ in 0..<50 {
            // A random G1 state: oriented pieces, slice edges in the slice.
            var state = CubeState.solved
            state.cornerPermutation = Array(0..<8).shuffled(using: &rng)
            state.edgePermutation = Array(0..<8).shuffled(using: &rng)
                + Array(8..<12).shuffled(using: &rng)
            let cornerPerm = Coordinates.cornerPermutation(of: state)
            let udEdgePerm = Coordinates.udEdgePermutation(of: state)
            let slicePerm = Coordinates.sliceEdgePermutation(of: state)
            for (index, rawMove) in SolverTables.phase2Moves.enumerated() {
                let moved = state.applying(Move(rawValue: rawMove)!)
                #expect(Int(tables.cornerPermutationMove[cornerPerm * 10 + index])
                    == Coordinates.cornerPermutation(of: moved))
                #expect(Int(tables.udEdgePermutationMove[udEdgePerm * 10 + index])
                    == Coordinates.udEdgePermutation(of: moved))
                #expect(Int(tables.sliceEdgePermutationMove[slicePerm * 10 + index])
                    == Coordinates.sliceEdgePermutation(of: moved))
            }
        }
    }

    @Test func cacheRoundTrips() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CubeKitCacheRoundTrip-\(UInt32.random(in: 0..<UInt32.max))")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try SolverTables.cached(in: directory)
        let second = try SolverTables.cached(in: directory)
        #expect(first.twistMove == second.twistMove)
        #expect(first.flipMove == second.flipMove)
        #expect(first.sliceMove == second.sliceMove)
        #expect(first.cornerPermutationMove == second.cornerPermutationMove)
        #expect(first.udEdgePermutationMove == second.udEdgePermutationMove)
        #expect(first.sliceEdgePermutationMove == second.sliceEdgePermutationMove)
        #expect(first.prune1SliceFlip == second.prune1SliceFlip)
        #expect(first.prune1SliceTwist == second.prune1SliceTwist)
        #expect(first.prune2SliceCorner == second.prune2SliceCorner)
        #expect(first.prune2SliceEdge == second.prune2SliceEdge)
    }
}
