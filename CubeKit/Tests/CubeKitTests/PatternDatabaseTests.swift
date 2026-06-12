import Foundation
import Testing
@testable import CubeKit

@Suite struct PartialPermutationTests {
    @Test func rankRoundTrips() {
        for k in [1, 3, 4, 8] {
            let count = PartialPermutation.count(slots: 12, pieces: k)
            let step = max(1, count / 500)
            for rank in stride(from: 0, to: count, by: step) {
                let positions = PartialPermutation.unrank(rank, slots: 12, pieces: k)
                #expect(Set(positions).count == k)
                #expect(PartialPermutation.rank(positions, slots: 12) == rank)
            }
        }
    }

    @Test func sequentialDecoderMatchesUnrank() {
        let count = PartialPermutation.count(slots: 12, pieces: 3)
        var decoder = PartialPermutation.SequentialDecoder(slots: 12, pieces: 3)
        for rank in 0..<count {
            #expect(decoder.positions == PartialPermutation.unrank(rank, slots: 12, pieces: 3),
                    "rank \(rank)")
            let advanced = decoder.advance()
            #expect(advanced == (rank < count - 1))
        }
    }

    @Test func decoderSeedsAtArbitraryRank() {
        var decoder = PartialPermutation.SequentialDecoder(
            slots: 12, pieces: 4, startRank: 5000)
        for rank in 5000..<5200 {
            #expect(decoder.positions == PartialPermutation.unrank(rank, slots: 12, pieces: 4))
            _ = decoder.advance()
        }
    }
}

/// Small-tier database used across the suite (generated once, cached in
/// the shared temp directory like the solver tables).
private enum TestPDB {
    static let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("CubeKitTestPDB")

    static let edgeSpec = PDBSpec(kind: .edges([0, 1, 2, 3]), fileName: "test-edges-4.pdb")
    static let cornerSpec = PDBSpec(kind: .corners, fileName: "optimal-corners.pdb")

    static let tables: (edges: PatternDatabase, corners: PatternDatabase) = {
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        for spec in [edgeSpec, cornerSpec] {
            let url = directory.appendingPathComponent(spec.fileName)
            if !FileManager.default.fileExists(atPath: url.path) {
                try! PatternDatabaseSet.generateTable(
                    spec: spec, to: url, report: { _, _ in }, isCancelled: { false })
            }
        }
        return (
            try! PatternDatabase(spec: edgeSpec, directory: directory),
            try! PatternDatabase(spec: cornerSpec, directory: directory)
        )
    }()
}

@Suite struct PatternDatabaseTests {
    @Test func indexTransitionsMatchCubieGroundTruth() {
        var rng = SeededRandom(seed: 61)
        for spec in [TestPDB.edgeSpec, TestPDB.cornerSpec] {
            let (destination, orientationDelta) = spec.moveTables()
            for _ in 0..<30 {
                let state = Scrambler.randomState(using: &rng)
                for move in Move.allCases {
                    // Ground truth: index of the moved cube state.
                    let expected = spec.index(of: state.applying(move))
                    // Transform the projection directly via the tables.
                    let permutation: [Int]
                    let orientationBySlot: [Int]
                    switch spec.kind {
                    case .corners:
                        permutation = state.cornerPermutation
                        orientationBySlot = state.cornerOrientation
                    case .edges:
                        permutation = state.edgePermutation
                        orientationBySlot = state.edgeOrientation
                    }
                    var positions: [Int] = []
                    var orientations: [Int] = []
                    for piece in spec.trackedPieces {
                        let slot = permutation.firstIndex(of: piece)!
                        positions.append(Int(destination[move.rawValue * spec.slots + slot]))
                        orientations.append(
                            (orientationBySlot[slot]
                                + Int(orientationDelta[move.rawValue * spec.slots + slot]))
                                % spec.orientationRadix)
                    }
                    var orientationValue = 0
                    for i in 0..<spec.orientationDigits {
                        orientationValue = orientationValue * spec.orientationRadix
                            + orientations[i]
                    }
                    let transformed = PartialPermutation.rank(positions, slots: spec.slots)
                        * spec.orientationCount + orientationValue
                    #expect(transformed == expected, "\(spec.fileName) move \(move)")
                }
            }
        }
    }

    @Test func solvedDistanceIsZero() {
        #expect(TestPDB.tables.edges.distance(of: .solved) == 0)
        #expect(TestPDB.tables.corners.distance(of: .solved) == 0)
    }

    @Test func neighborDistancesDifferByAtMostOne() {
        var rng = SeededRandom(seed: 62)
        for _ in 0..<100 {
            let state = Scrambler.randomState(using: &rng)
            for table in [TestPDB.tables.edges, TestPDB.tables.corners] {
                let h = table.distance(of: state)
                for move in Move.allCases {
                    let neighbor = table.distance(of: state.applying(move))
                    #expect(abs(h - neighbor) <= 1)
                }
            }
        }
    }

    @Test func distancesAreAdmissible() {
        // A scramble of length j can never leave the projection more
        // than j moves from solved.
        var rng = SeededRandom(seed: 63)
        for length in 1...10 {
            for _ in 0..<20 {
                let moves = (0..<length).map { _ in Move.allCases.randomElement(using: &rng)! }
                let state = CubeState.solved.applying(moves)
                #expect(TestPDB.tables.edges.distance(of: state) <= length)
                #expect(TestPDB.tables.corners.distance(of: state) <= length)
            }
        }
    }

    @Test func cornerDistancesAreExactForShortOptimalScrambles() {
        // The corner PDB is the exact corner-space distance: a one-move
        // scramble must be distance 1.
        for move in Move.allCases {
            #expect(TestPDB.tables.corners.distance(of: CubeState.solved.applying(move)) == 1)
        }
    }

    @Test func seedsRoundTrip() throws {
        _ = TestPDB.tables  // force generation of the table files first
        let seedDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CubeKitSeedTest-\(UInt32.random(in: 0..<UInt32.max))")
        let restoreDir = seedDir.appendingPathComponent("restored")
        defer { try? FileManager.default.removeItem(at: seedDir) }

        // Compress the small test edge table, then decompress and
        // compare bytes.
        let original = TestPDB.directory.appendingPathComponent(TestPDB.edgeSpec.fileName)
        try FileManager.default.createDirectory(
            at: restoreDir, withIntermediateDirectories: true)
        let names = [TestPDB.edgeSpec.fileName]
        for name in names {
            let seed = seedDir.appendingPathComponent(
                PatternDatabaseSet.seedFileName(for: name))
            try FileManager.default.createDirectory(
                at: seedDir, withIntermediateDirectories: true)
            try PatternDatabaseSet.compressForTesting(from: original, to: seed)
            let restored = restoreDir.appendingPathComponent(name)
            try PatternDatabaseSet.decompressForTesting(from: seed, to: restored)
            #expect(
                try Data(contentsOf: restored) == Data(contentsOf: original),
                "seed round trip \(name)")
        }
    }
}
