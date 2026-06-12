import Foundation

/// Precomputed move and pruning tables for the two-phase solver
/// (~5.5 MB). Generation takes well under a second in release builds;
/// use `cached(in:)` to persist across launches.
public final class SolverTables: Sendable {
    /// The ten moves that stay inside G1: U, U2, U', D, D2, D', R2, L2,
    /// F2, B2 — as `Move` raw values.
    static let phase2Moves: [Int] = [0, 1, 2, 9, 10, 11, 4, 13, 7, 16]

    // Phase 1 move tables, indexed [coordinate * 18 + move].
    let twistMove: [UInt16]
    let flipMove: [UInt16]
    let sliceMove: [UInt16]

    // Phase 2 move tables, indexed [coordinate * 10 + phase2MoveIndex].
    let cornerPermutationMove: [UInt16]
    let udEdgePermutationMove: [UInt16]
    let sliceEdgePermutationMove: [UInt16]

    // Pruning tables: exact distances in the projected spaces.
    let prune1SliceFlip: [Int8]   // [slice * 2048 + flip]
    let prune1SliceTwist: [Int8]  // [slice * 2187 + twist]
    let prune2SliceCorner: [Int8] // [slicePerm * 40320 + cornerPerm]
    let prune2SliceEdge: [Int8]   // [slicePerm * 40320 + udEdgePerm]

    // MARK: Generation

    public static func generate() -> SolverTables {
        SolverTables()
    }

    private init() {
        // Corner/edge permutation and orientation actions of the six
        // basic moves, flattened for the generators.
        let moves = CubeState.basicMoves

        twistMove = TableBuilder.orientationTable(
            count: Coordinates.twistCount, pieceCount: 8, modulus: 3,
            decode: Coordinates.cornerOrientations(forTwist:),
            encode: { orientations in
                var value = 0
                for i in 0..<7 { value = value * 3 + orientations[i] }
                return value
            },
            movePermutation: { moves[$0].cornerPermutation },
            moveOrientation: { moves[$0].cornerOrientation }
        )

        flipMove = TableBuilder.orientationTable(
            count: Coordinates.flipCount, pieceCount: 12, modulus: 2,
            decode: Coordinates.edgeOrientations(forFlip:),
            encode: { orientations in
                var value = 0
                for i in 0..<11 { value = value * 2 + orientations[i] }
                return value
            },
            movePermutation: { moves[$0].edgePermutation },
            moveOrientation: { moves[$0].edgeOrientation }
        )

        // Slice table: representative places slice edges at the ranked
        // positions; the filler arrangement is irrelevant to the result.
        sliceMove = TableBuilder.occupancyTable(
            slotCount: 12, markerCount: 4, totalSlots: 12, moves: Array(0..<18),
            movePermutation: { moves[$0].edgePermutation }
        )

        cornerPermutationMove = TableBuilder.permutationTable(
            count: Coordinates.cornerPermutationCount, pieceCount: 8,
            moves: Self.phase2Moves,
            movePermutation: { moves[$0].cornerPermutation },
            project: { $0 }, embed: { $0 }
        )

        udEdgePermutationMove = TableBuilder.permutationTable(
            count: Coordinates.udEdgePermutationCount, pieceCount: 8,
            moves: Self.phase2Moves,
            movePermutation: { moves[$0].edgePermutation },
            project: { Array($0[0..<8]) },
            embed: { $0 + [8, 9, 10, 11] }
        )

        sliceEdgePermutationMove = TableBuilder.permutationTable(
            count: Coordinates.sliceEdgePermutationCount, pieceCount: 4,
            moves: Self.phase2Moves,
            movePermutation: { moves[$0].edgePermutation },
            project: { $0[8..<12].map { $0 - 8 } },
            embed: { Array(0..<8) + $0.map { $0 + 8 } }
        )

        // Pruning tables: BFS from the solved projection.
        let twistMove = self.twistMove
        let flipMove = self.flipMove
        let sliceMove = self.sliceMove
        let cornerPermutationMove = self.cornerPermutationMove
        let udEdgePermutationMove = self.udEdgePermutationMove
        let sliceEdgePermutationMove = self.sliceEdgePermutationMove

        prune1SliceFlip = TableBuilder.breadthFirstDistances(
            stateCount: Coordinates.sliceCount * Coordinates.flipCount,
            moveCount: 18,
            starts: [Coordinates.solvedSlice * Coordinates.flipCount]
        ) { state, move in
            let slice = state / Coordinates.flipCount
            let flip = state % Coordinates.flipCount
            return Int(sliceMove[slice * 18 + move]) * Coordinates.flipCount
                + Int(flipMove[flip * 18 + move])
        }

        prune1SliceTwist = TableBuilder.breadthFirstDistances(
            stateCount: Coordinates.sliceCount * Coordinates.twistCount,
            moveCount: 18,
            starts: [Coordinates.solvedSlice * Coordinates.twistCount]
        ) { state, move in
            let slice = state / Coordinates.twistCount
            let twist = state % Coordinates.twistCount
            return Int(sliceMove[slice * 18 + move]) * Coordinates.twistCount
                + Int(twistMove[twist * 18 + move])
        }

        prune2SliceCorner = TableBuilder.breadthFirstDistances(
            stateCount: Coordinates.sliceEdgePermutationCount * Coordinates.cornerPermutationCount,
            moveCount: 10,
            starts: [0]
        ) { state, move in
            let slicePerm = state / Coordinates.cornerPermutationCount
            let cornerPerm = state % Coordinates.cornerPermutationCount
            return Int(sliceEdgePermutationMove[slicePerm * 10 + move])
                * Coordinates.cornerPermutationCount
                + Int(cornerPermutationMove[cornerPerm * 10 + move])
        }

        prune2SliceEdge = TableBuilder.breadthFirstDistances(
            stateCount: Coordinates.sliceEdgePermutationCount * Coordinates.udEdgePermutationCount,
            moveCount: 10,
            starts: [0]
        ) { state, move in
            let slicePerm = state / Coordinates.udEdgePermutationCount
            let edgePerm = state % Coordinates.udEdgePermutationCount
            return Int(sliceEdgePermutationMove[slicePerm * 10 + move])
                * Coordinates.udEdgePermutationCount
                + Int(udEdgePermutationMove[edgePerm * 10 + move])
        }
    }

    private init(
        twistMove: [UInt16], flipMove: [UInt16], sliceMove: [UInt16],
        cornerPermutationMove: [UInt16], udEdgePermutationMove: [UInt16],
        sliceEdgePermutationMove: [UInt16],
        prune1SliceFlip: [Int8], prune1SliceTwist: [Int8],
        prune2SliceCorner: [Int8], prune2SliceEdge: [Int8]
    ) {
        self.twistMove = twistMove
        self.flipMove = flipMove
        self.sliceMove = sliceMove
        self.cornerPermutationMove = cornerPermutationMove
        self.udEdgePermutationMove = udEdgePermutationMove
        self.sliceEdgePermutationMove = sliceEdgePermutationMove
        self.prune1SliceFlip = prune1SliceFlip
        self.prune1SliceTwist = prune1SliceTwist
        self.prune2SliceCorner = prune2SliceCorner
        self.prune2SliceEdge = prune2SliceEdge
    }

    // MARK: Disk cache

    private static let cacheVersion: UInt32 = 1
    private static let cacheMagic: UInt32 = 0x434B_3154  // "CK1T"

    /// Loads tables from `directory`, generating and saving them on a
    /// cache miss. The file is device-local (native byte order).
    public static func cached(in directory: URL) throws -> SolverTables {
        let url = directory.appendingPathComponent("kociemba-tables.bin")
        if let data = try? Data(contentsOf: url), let tables = decode(data) {
            return tables
        }
        let tables = generate()
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        try tables.encoded().write(to: url, options: .atomic)
        return tables
    }

    private func encoded() -> Data {
        var data = Data()
        func append(_ value: UInt32) {
            withUnsafeBytes(of: value) { data.append(contentsOf: $0) }
        }
        func append16(_ table: [UInt16]) {
            append(UInt32(table.count))
            table.withUnsafeBytes { data.append(contentsOf: $0) }
        }
        func append8(_ table: [Int8]) {
            append(UInt32(table.count))
            table.withUnsafeBytes { data.append(contentsOf: $0) }
        }
        append(Self.cacheMagic)
        append(Self.cacheVersion)
        append16(twistMove)
        append16(flipMove)
        append16(sliceMove)
        append16(cornerPermutationMove)
        append16(udEdgePermutationMove)
        append16(sliceEdgePermutationMove)
        append8(prune1SliceFlip)
        append8(prune1SliceTwist)
        append8(prune2SliceCorner)
        append8(prune2SliceEdge)
        return data
    }

    private static func decode(_ data: Data) -> SolverTables? {
        var offset = 0
        func readUInt32() -> UInt32? {
            guard offset + 4 <= data.count else { return nil }
            let value = data.withUnsafeBytes {
                $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
            }
            offset += 4
            return value
        }
        func read16(expectedCount: Int) -> [UInt16]? {
            guard let count = readUInt32(), Int(count) == expectedCount,
                  offset + expectedCount * 2 <= data.count else { return nil }
            let table = [UInt16](unsafeUninitializedCapacity: expectedCount) { buffer, written in
                data.withUnsafeBytes { raw in
                    let source = raw.baseAddress!.advanced(by: offset)
                    memcpy(buffer.baseAddress!, source, expectedCount * 2)
                }
                written = expectedCount
            }
            offset += expectedCount * 2
            return table
        }
        func read8(expectedCount: Int) -> [Int8]? {
            guard let count = readUInt32(), Int(count) == expectedCount,
                  offset + expectedCount <= data.count else { return nil }
            let table = [Int8](unsafeUninitializedCapacity: expectedCount) { buffer, written in
                data.withUnsafeBytes { raw in
                    let source = raw.baseAddress!.advanced(by: offset)
                    memcpy(buffer.baseAddress!, source, expectedCount)
                }
                written = expectedCount
            }
            offset += expectedCount
            return table
        }

        guard readUInt32() == cacheMagic, readUInt32() == cacheVersion,
              let twistMove = read16(expectedCount: Coordinates.twistCount * 18),
              let flipMove = read16(expectedCount: Coordinates.flipCount * 18),
              let sliceMove = read16(expectedCount: Coordinates.sliceCount * 18),
              let cornerPermutationMove = read16(
                expectedCount: Coordinates.cornerPermutationCount * 10),
              let udEdgePermutationMove = read16(
                expectedCount: Coordinates.udEdgePermutationCount * 10),
              let sliceEdgePermutationMove = read16(
                expectedCount: Coordinates.sliceEdgePermutationCount * 10),
              let prune1SliceFlip = read8(
                expectedCount: Coordinates.sliceCount * Coordinates.flipCount),
              let prune1SliceTwist = read8(
                expectedCount: Coordinates.sliceCount * Coordinates.twistCount),
              let prune2SliceCorner = read8(
                expectedCount: Coordinates.sliceEdgePermutationCount
                    * Coordinates.cornerPermutationCount),
              let prune2SliceEdge = read8(
                expectedCount: Coordinates.sliceEdgePermutationCount
                    * Coordinates.udEdgePermutationCount),
              offset == data.count
        else { return nil }

        return SolverTables(
            twistMove: twistMove, flipMove: flipMove, sliceMove: sliceMove,
            cornerPermutationMove: cornerPermutationMove,
            udEdgePermutationMove: udEdgePermutationMove,
            sliceEdgePermutationMove: sliceEdgePermutationMove,
            prune1SliceFlip: prune1SliceFlip, prune1SliceTwist: prune1SliceTwist,
            prune2SliceCorner: prune2SliceCorner, prune2SliceEdge: prune2SliceEdge
        )
    }
}
