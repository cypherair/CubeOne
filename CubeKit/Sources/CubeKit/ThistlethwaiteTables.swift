import Foundation

/// Exact BFS distance tables for the four Thistlethwaite phases (~5 MB).
/// Each table measures, in the move set allowed for that phase, the
/// distance to the next subgroup in the chain G0 ⊃ G1 ⊃ G2 ⊃ G3 ⊃ G4,
/// so a solve is a greedy descent — every phase comes out
/// phase-optimal. Generation takes about a second in release builds;
/// use `cached(in:)` to persist across launches.
public final class ThistlethwaiteTables: Sendable {
    /// Moves allowed in each phase, as `Move` raw values. Every set is
    /// closed under inverses — that is what guarantees the greedy
    /// descent always finds a distance-reducing move (the move graph is
    /// undirected, so a BFS parent edge runs backwards from any state).
    static let phaseMoves: [[Int]] = [
        Array(0..<18),                                      // G0: everything
        [0, 1, 2, 9, 10, 11, 12, 13, 14, 3, 4, 5, 7, 16],   // G1: U* D* L* R* F2 B2
        SolverTables.phase2Moves,                           // G2: U* D* R2 L2 F2 B2
        [1, 10, 4, 13, 7, 16],                              // G3: half turns only
    ]

    /// The M-slice edge pieces (UF, UB, DF, DB) live in the U/D layers,
    /// slots 0–7, once the cube is in G2.
    static let mEdges: Set<Int> = [1, 3, 5, 7]
    static let separationCount = 70  // C(8,4)

    static let corner96Count = 96
    static let sliceEdgeArrangements = 13824  // 24³
    static let phase4Count = 96 * 13824

    // Distance tables. Phase 4 legitimately covers only half its index
    // space (half turns are even permutations, so odd combined edge
    // parity is unreachable); unreached entries stay -1.
    let phase1: [Int8]  // [flip]
    let phase2: [Int8]  // [twist * 495 + slice]
    let phase3: [Int8]  // [cornerPermutation * 70 + mSeparation]
    let phase4: [Int8]  // [corner96 * 13824 + ((mPerm * 24) + sPerm) * 24 + ePerm]

    /// Lehmer ranks of the 96 corner permutations reachable by half
    /// turns, mapped to dense indices for the phase-4 coordinate.
    let corner96Index: [Int: Int]

    // MARK: Generation

    public static func generate() -> ThistlethwaiteTables {
        ThistlethwaiteTables()
    }

    private init() {
        let moves = CubeState.basicMoves
        let corner96 = Self.corner96Indices()
        corner96Index = corner96

        // Phase 1 — orient every edge: the flip coordinate alone.
        let flipMove = TableBuilder.orientationTable(
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
        phase1 = TableBuilder.breadthFirstDistances(
            stateCount: Coordinates.flipCount, moveCount: 18, starts: [0]
        ) { state, move in
            Int(flipMove[state * 18 + move])
        }

        // Phase 2 — orient corners and bring the E-slice edges into the
        // E slice, using G1 moves only.
        let twistMove = TableBuilder.orientationTable(
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
        let sliceMove = TableBuilder.occupancyTable(
            slotCount: 12, markerCount: 4, totalSlots: 12, moves: Array(0..<18),
            movePermutation: { moves[$0].edgePermutation }
        )
        let g1 = Self.phaseMoves[1]
        phase2 = TableBuilder.breadthFirstDistances(
            stateCount: Coordinates.twistCount * Coordinates.sliceCount,
            moveCount: g1.count,
            starts: [Coordinates.solvedSlice]  // twist 0, slice solved
        ) { state, index in
            let move = g1[index]
            let twist = state / Coordinates.sliceCount
            let slice = state % Coordinates.sliceCount
            return Int(twistMove[twist * 18 + move]) * Coordinates.sliceCount
                + Int(sliceMove[slice * 18 + move])
        }

        // Phase 3 — into the square group: corner permutation and
        // M-edge separation, using G2 moves only. The goal is the whole
        // coset (every half-turn-reachable corner permutation with the
        // M edges home), seeded as a multi-source BFS — that sidesteps
        // hand-deriving Thistlethwaite's tetrad-twist condition.
        let g2 = Self.phaseMoves[2]
        let cornerPermutationMove = TableBuilder.permutationTable(
            count: Coordinates.cornerPermutationCount, pieceCount: 8, moves: g2,
            movePermutation: { moves[$0].cornerPermutation },
            project: { $0 }, embed: { $0 }
        )
        let separationMove = TableBuilder.occupancyTable(
            slotCount: 8, markerCount: 4, totalSlots: 12, moves: g2,
            movePermutation: { moves[$0].edgePermutation }
        )
        let solvedSeparation = Self.mSeparation(of: .solved)
        phase3 = TableBuilder.breadthFirstDistances(
            stateCount: Coordinates.cornerPermutationCount * Self.separationCount,
            moveCount: g2.count,
            starts: corner96.keys.map {
                $0 * Self.separationCount + solvedSeparation
            }
        ) { state, index in
            let corner = state / Self.separationCount
            let separation = state % Self.separationCount
            return Int(cornerPermutationMove[corner * g2.count + index])
                * Self.separationCount
                + Int(separationMove[separation * g2.count + index])
        }

        // Phase 4 — finish inside the square group with half turns.
        var corner96Move = [UInt16](repeating: 0, count: Self.corner96Count * 6)
        for (rank, index) in corner96 {
            let permutation = Coordinates.unrankPermutation(rank, count: 8)
            for face in 0..<6 {
                let moved = TableBuilder.permutationApplying(
                    permutation, moves[face].cornerPermutation, times: 2)
                corner96Move[index * 6 + face] =
                    UInt16(corner96[Coordinates.rankPermutation(moved)]!)
            }
        }
        let mMove = Self.sliceClassMove(slots: [1, 3, 5, 7])
        let sMove = Self.sliceClassMove(slots: [0, 2, 4, 6])
        let eMove = Self.sliceClassMove(slots: [8, 9, 10, 11])
        phase4 = TableBuilder.breadthFirstDistances(
            stateCount: Self.phase4Count, moveCount: 6,
            starts: [corner96[0]! * Self.sliceEdgeArrangements],
            requireFullCoverage: false
        ) { state, face in
            let e = state % 24
            let s = (state / 24) % 24
            let m = (state / 576) % 24
            let corner = state / Self.sliceEdgeArrangements
            return Int(corner96Move[corner * 6 + face]) * Self.sliceEdgeArrangements
                + Int(mMove[m * 6 + face]) * 576
                + Int(sMove[s * 6 + face]) * 24
                + Int(eMove[e * 6 + face])
        }
        assert(
            phase4.lazy.filter { $0 >= 0 }.count == Self.phase4Count / 2,
            "square group should fill exactly half the phase-4 space")
    }

    private init(phase1: [Int8], phase2: [Int8], phase3: [Int8], phase4: [Int8]) {
        self.phase1 = phase1
        self.phase2 = phase2
        self.phase3 = phase3
        self.phase4 = phase4
        corner96Index = Self.corner96Indices()
    }

    // MARK: Coordinates

    /// Colex rank of which of the eight U/D slots hold the M-slice
    /// edges. Defined once the cube is in G2.
    static func mSeparation(of state: CubeState) -> Int {
        var rank = 0
        var found = 0
        for slot in 0..<8 where mEdges.contains(state.edgePermutation[slot]) {
            found += 1
            rank += Coordinates.binomial[slot][found]
        }
        return rank
    }

    /// The distance left in `phase` (0–3) for a state that has completed
    /// the phases before it, or nil if the state is outside the phase's
    /// domain (which means an earlier phase failed).
    func distance(of state: CubeState, phase: Int) -> Int? {
        switch phase {
        case 0:
            return Int(phase1[Coordinates.flip(of: state)])
        case 1:
            return Int(phase2[
                Coordinates.twist(of: state) * Coordinates.sliceCount
                    + Coordinates.slice(of: state)])
        case 2:
            return Int(phase3[
                Coordinates.rankPermutation(state.cornerPermutation) * Self.separationCount
                    + Self.mSeparation(of: state)])
        default:
            guard let corner = corner96Index[
                Coordinates.rankPermutation(state.cornerPermutation)],
                let m = Self.classPermutation(of: state, slots: [1, 3, 5, 7]),
                let s = Self.classPermutation(of: state, slots: [0, 2, 4, 6]),
                let e = Self.classPermutation(of: state, slots: [8, 9, 10, 11])
            else { return nil }
            let index = corner * Self.sliceEdgeArrangements
                + (Coordinates.rankPermutation(m) * 24 + Coordinates.rankPermutation(s)) * 24
                + Coordinates.rankPermutation(e)
            let value = phase4[index]
            return value < 0 ? nil : Int(value)
        }
    }

    /// The within-class permutation of one edge slice (indices into
    /// `slots`), or nil if a foreign piece sits in the class.
    private static func classPermutation(of state: CubeState, slots: [Int]) -> [Int]? {
        var permutation: [Int] = []
        for slot in slots {
            guard let index = slots.firstIndex(of: state.edgePermutation[slot])
            else { return nil }
            permutation.append(index)
        }
        return permutation
    }

    /// The 96 corner permutations reachable by half turns, as Lehmer
    /// rank → dense index. Sub-millisecond, so recomputed on every init
    /// rather than persisted.
    private static func corner96Indices() -> [Int: Int] {
        var visited: Set<Int> = [0]
        var queue: [[Int]] = [Array(0..<8)]
        var head = 0
        while head < queue.count {
            let permutation = queue[head]
            head += 1
            for face in 0..<6 {
                let moved = TableBuilder.permutationApplying(
                    permutation, CubeState.basicMoves[face].cornerPermutation, times: 2)
                if visited.insert(Coordinates.rankPermutation(moved)).inserted {
                    queue.append(moved)
                }
            }
        }
        assert(visited.count == corner96Count, "half-turn corner closure should be 96")
        var indices: [Int: Int] = [:]
        for (index, rank) in visited.sorted().enumerated() {
            indices[rank] = index
        }
        return indices
    }

    /// Half-turn move table for the within-class permutation of one edge
    /// slice (each half turn maps every slice class to itself).
    private static func sliceClassMove(slots: [Int]) -> [UInt16] {
        var table = [UInt16](repeating: 0, count: 24 * 6)
        for rank in 0..<24 {
            let classPermutation = Coordinates.unrankPermutation(rank, count: 4)
            var full = Array(0..<12)
            for (i, slot) in slots.enumerated() { full[slot] = slots[classPermutation[i]] }
            for face in 0..<6 {
                let moved = TableBuilder.permutationApplying(
                    full, CubeState.basicMoves[face].edgePermutation, times: 2)
                let projected = slots.map { slot in slots.firstIndex(of: moved[slot])! }
                table[rank * 6 + face] = UInt16(Coordinates.rankPermutation(projected))
            }
        }
        return table
    }

    // MARK: Disk cache

    private static let cacheVersion: UInt32 = 1
    private static let cacheMagic: UInt32 = 0x434B_3157  // "CK1W"

    /// Loads tables from `directory`, generating and saving them on a
    /// cache miss. The file is device-local (native byte order).
    public static func cached(in directory: URL) throws -> ThistlethwaiteTables {
        let url = directory.appendingPathComponent("thistlethwaite-tables.bin")
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
        func append8(_ table: [Int8]) {
            append(UInt32(table.count))
            table.withUnsafeBytes { data.append(contentsOf: $0) }
        }
        append(Self.cacheMagic)
        append(Self.cacheVersion)
        append8(phase1)
        append8(phase2)
        append8(phase3)
        append8(phase4)
        return data
    }

    private static func decode(_ data: Data) -> ThistlethwaiteTables? {
        var offset = 0
        func readUInt32() -> UInt32? {
            guard offset + 4 <= data.count else { return nil }
            let value = data.withUnsafeBytes {
                $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
            }
            offset += 4
            return value
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
              let phase1 = read8(expectedCount: Coordinates.flipCount),
              let phase2 = read8(
                expectedCount: Coordinates.twistCount * Coordinates.sliceCount),
              let phase3 = read8(
                expectedCount: Coordinates.cornerPermutationCount * separationCount),
              let phase4 = read8(expectedCount: phase4Count),
              offset == data.count
        else { return nil }

        return ThistlethwaiteTables(
            phase1: phase1, phase2: phase2, phase3: phase3, phase4: phase4)
    }
}
