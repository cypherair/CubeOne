import Foundation

/// Finds a provably shortest solution (Korf-style IDA* over pattern
/// databases). Typical random cubes (optimal 17–18 moves) take minutes
/// with the 8-edge tier; the search is synchronous and should run on a
/// background task.
public final class OptimalSolver: Sendable {
    public struct Progress: Sendable {
        public let currentBound: Int
        public let upperBound: Int?
        public let nodesSearched: Int64
        public let elapsed: Duration
    }

    private let databases: PatternDatabaseSet
    private let upperBoundSolver: KociembaSolver?

    public init(databases: PatternDatabaseSet, upperBoundSolver: KociembaSolver?) {
        self.databases = databases
        self.upperBoundSolver = upperBoundSolver
    }

    /// Returns a shortest solution, the two-phase solution when that is
    /// proven optimal, or nil when cancelled (or the state is illegal).
    public func solve(
        _ state: CubeState,
        progress: @escaping @Sendable (Progress) -> Void = { _ in },
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) -> [Move]? {
        guard state.isLegal else { return nil }
        if state.isSolved { return [] }

        let clock = ContinuousClock()
        let started = clock.now

        // Instant upper bound: if IDA* exhausts every depth below it,
        // the two-phase answer is itself a proven-optimal solution.
        let upperBoundSolution = upperBoundSolver?.solve(
            state, timeBudget: .milliseconds(2000))
        let upperBound = upperBoundSolution?.count

        let engine = SearchEngine(databases: databases)
        let root = FastCube(state)
        let rootHeuristic = engine.heuristic(of: root)
        let nodes = SharedCounter()
        let abort = SharedFlag()

        var bound = rootHeuristic
        progress(Progress(
            currentBound: bound, upperBound: upperBound,
            nodesSearched: 0, elapsed: clock.now - started))
        while upperBound.map({ bound < $0 }) ?? true {
            if isCancelled() { return nil }
            progress(Progress(
                currentBound: bound, upperBound: upperBound,
                nodesSearched: nodes.value, elapsed: clock.now - started))

            // Periodic progress/cancellation pump while workers run. On
            // the main queue: global utility queues starve while the
            // search saturates every core.
            let pump = DispatchSource.makeTimerSource(queue: .main)
            pump.schedule(deadline: .now() + 0.25, repeating: 0.25)
            let boundForPump = bound
            pump.setEventHandler {
                if isCancelled() { abort.set() }
                progress(Progress(
                    currentBound: boundForPump, upperBound: upperBound,
                    nodesSearched: nodes.value, elapsed: clock.now - started))
            }
            pump.resume()
            let solution = engine.searchExhaustively(
                root: root, bound: bound, nodes: nodes, abort: abort)
            pump.cancel()

            if isCancelled() { return nil }
            if let solution {
                return solution
            }
            bound += 1
        }
        // Every depth below the two-phase length is exhausted.
        return upperBoundSolution
    }
}

// MARK: - Fast cube representation

/// Fixed-size, allocation-free cube state for the search hot path.
struct FastCube {
    var cornerPermutation: SIMD8<UInt8>
    var cornerOrientation: SIMD8<UInt8>
    var edgePermutation: SIMD16<UInt8>
    var edgeOrientation: SIMD16<UInt8>

    init(_ state: CubeState) {
        var cp = SIMD8<UInt8>(repeating: 0)
        var co = SIMD8<UInt8>(repeating: 0)
        for i in 0..<8 {
            cp[i] = UInt8(state.cornerPermutation[i])
            co[i] = UInt8(state.cornerOrientation[i])
        }
        cornerPermutation = cp
        cornerOrientation = co
        var ep = SIMD16<UInt8>(repeating: 0)
        var eo = SIMD16<UInt8>(repeating: 0)
        for i in 0..<12 {
            ep[i] = UInt8(state.edgePermutation[i])
            eo[i] = UInt8(state.edgeOrientation[i])
        }
        edgePermutation = ep
        edgeOrientation = eo
    }

    /// Per-move source maps and orientation deltas, flattened from
    /// `CubeState.basicMoves` (move m's table at offset m).
    struct MoveTables {
        var cornerSource: [SIMD8<UInt8>] = []
        var cornerDelta: [SIMD8<UInt8>] = []
        var edgeSource: [SIMD16<UInt8>] = []
        var edgeDelta: [SIMD16<UInt8>] = []

        init() {
            for move in Move.allCases {
                let state = CubeState.solved.applying(move)
                var cs = SIMD8<UInt8>(repeating: 0)
                var cd = SIMD8<UInt8>(repeating: 0)
                for i in 0..<8 {
                    cs[i] = UInt8(state.cornerPermutation[i])
                    cd[i] = UInt8(state.cornerOrientation[i])
                }
                var es = SIMD16<UInt8>(repeating: 0)
                var ed = SIMD16<UInt8>(repeating: 0)
                for i in 0..<12 {
                    es[i] = UInt8(state.edgePermutation[i])
                    ed[i] = UInt8(state.edgeOrientation[i])
                }
                cornerSource.append(cs)
                cornerDelta.append(cd)
                edgeSource.append(es)
                edgeDelta.append(ed)
            }
        }
    }

    static let moveTables = MoveTables()

    @inline(__always)
    func applying(_ move: Int) -> FastCube {
        let tables = Self.moveTables
        var result = self
        let cs = tables.cornerSource[move]
        let cd = tables.cornerDelta[move]
        for i in 0..<8 {
            let from = Int(cs[i])
            result.cornerPermutation[i] = cornerPermutation[from]
            var ori = cornerOrientation[from] + cd[i]
            if ori >= 3 { ori -= 3 }
            result.cornerOrientation[i] = ori
        }
        let es = tables.edgeSource[move]
        let ed = tables.edgeDelta[move]
        for i in 0..<12 {
            let from = Int(es[i])
            result.edgePermutation[i] = edgePermutation[from]
            result.edgeOrientation[i] = edgeOrientation[from] ^ ed[i]
        }
        return result
    }

    var isSolved: Bool {
        cornerPermutation == SIMD8(0, 1, 2, 3, 4, 5, 6, 7)
            && cornerOrientation == SIMD8(repeating: 0)
            && edgePermutation == SIMD16(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 0, 0, 0, 0)
            && edgeOrientation == SIMD16(repeating: 0)
    }
}

// MARK: - Search engine

/// The per-solve search machinery: PDB lookups specialized to the
/// loaded tier, exhaustive bounded DFS, and prefix-split parallelism.
final class SearchEngine: @unchecked Sendable {
    private let databases: PatternDatabaseSet
    private let cornerTable: UnsafePointer<UInt8>
    private let edgeTableA: UnsafePointer<UInt8>
    private let edgeTableB: UnsafePointer<UInt8>
    private let edgeSubsetSize: Int
    private let edgeOrientationCountA: Int
    /// First tracked piece of subset B (pieces run b0..<b0+k).
    private let edgeSubsetBStart: Int

    init(databases: PatternDatabaseSet) {
        self.databases = databases
        cornerTable = databases.tables[0].nibbleBase
        edgeTableA = databases.tables[1].nibbleBase
        edgeTableB = databases.tables[2].nibbleBase
        guard case .edges(let subsetA) = databases.tables[1].spec.kind,
              case .edges(let subsetB) = databases.tables[2].spec.kind
        else { fatalError("edge tables expected") }
        edgeSubsetSize = subsetA.count
        edgeOrientationCountA = 1 << subsetA.count
        edgeSubsetBStart = subsetB[0]
    }

    @inline(__always)
    private func nibble(_ table: UnsafePointer<UInt8>, _ index: Int) -> Int {
        let byte = table[index >> 1]
        return Int((index & 1) == 0 ? byte & 0xF : byte >> 4)
    }

    /// max(corner, edgeA, edgeB) — each an exact subproblem distance.
    @inline(__always)
    func heuristic(of cube: FastCube) -> Int {
        // Positions (slot of each piece) for corners and edges.
        var cornerPosition = SIMD8<UInt8>(repeating: 0)
        for slot in 0..<8 {
            cornerPosition[Int(cube.cornerPermutation[slot])] = UInt8(slot)
        }
        var edgePosition = SIMD16<UInt8>(repeating: 0)
        for slot in 0..<12 {
            edgePosition[Int(cube.edgePermutation[slot])] = UInt8(slot)
        }

        // Corner index: full Lehmer rank × 2187 + base-3 orientation of
        // pieces 0..6 (orientation digit of a piece = co at its slot).
        var rank = 0
        var used: UInt16 = 0
        var orientation = 0
        for piece in 0..<8 {
            let p = Int(cornerPosition[piece])
            rank = rank * (8 - piece) + p - (Int(used) & ((1 << p) - 1)).nonzeroBitCount
            used |= 1 << UInt16(p)
            if piece < 7 {
                orientation = orientation * 3 + Int(cube.cornerOrientation[p])
            }
        }
        var h = nibble(cornerTable, rank * 2187 + orientation)

        // Edge subset A: pieces 0..<k.
        h = max(h, edgeDistance(
            table: edgeTableA, firstPiece: 0, cube: cube, positions: edgePosition))
        // Edge subset B: pieces b0..<b0+k.
        h = max(h, edgeDistance(
            table: edgeTableB, firstPiece: edgeSubsetBStart, cube: cube,
            positions: edgePosition))
        return h
    }

    @inline(__always)
    private func edgeDistance(
        table: UnsafePointer<UInt8>, firstPiece: Int, cube: FastCube,
        positions: SIMD16<UInt8>
    ) -> Int {
        var rank = 0
        var used: UInt16 = 0
        var bits = 0
        for i in 0..<edgeSubsetSize {
            let p = Int(positions[firstPiece + i])
            rank = rank * (12 - i) + p - (Int(used) & ((1 << p) - 1)).nonzeroBitCount
            used |= 1 << UInt16(p)
            bits = (bits << 1) | Int(cube.edgeOrientation[p])
        }
        return nibble(table, rank * edgeOrientationCountA + bits)
    }

    // MARK: Bounded exhaustive search

    /// Searches all canonical sequences of exactly ≤ `bound` moves;
    /// returns a solution of length == bound if one exists. Splits the
    /// tree at shallow prefixes across cores for large bounds.
    func searchExhaustively(
        root: FastCube, bound: Int, nodes: SharedCounter, abort: SharedFlag
    ) -> [Move]? {
        abort.clear()
        if bound <= 5 {
            var path = [Int](repeating: 0, count: max(bound, 1))
            var local: Int64 = 0
            let found = depthFirst(
                cube: root, g: 0, bound: bound, lastFace: -1, path: &path,
                nodes: &local, abort: abort)
            nodes.add(local)
            return found ? path.map { Move(rawValue: $0)! } : nil
        }

        // Enumerate canonical 3-move prefixes worth searching.
        struct Prefix {
            let cube: FastCube
            let moves: [Int]
            let lastFace: Int
        }
        var prefixes: [Prefix] = []
        func extend(_ cube: FastCube, _ moves: [Int], _ lastFace: Int) {
            if moves.count == 3 {
                prefixes.append(Prefix(cube: cube, moves: moves, lastFace: lastFace))
                return
            }
            for move in 0..<18 {
                let face = move / 3
                guard Self.faceAllowed(face, after: lastFace) else { continue }
                let next = cube.applying(move)
                if heuristic(of: next) + moves.count + 1 <= bound {
                    extend(next, moves + [move], face)
                }
            }
        }
        extend(root, [], -1)
        if prefixes.isEmpty { return nil }

        let jobIndex = SharedCounter()
        let result = SharedResult()
        // Leave one core for the UI and the progress pump.
        let workers = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)
        DispatchQueue.concurrentPerform(iterations: workers) { _ in
            var path = [Int](repeating: 0, count: bound)
            var local: Int64 = 0
            while !abort.isSet {
                let index = Int(jobIndex.next() - 1)
                guard index < prefixes.count else { break }
                let prefix = prefixes[index]
                for (i, move) in prefix.moves.enumerated() { path[i] = move }
                let found = depthFirst(
                    cube: prefix.cube, g: prefix.moves.count, bound: bound,
                    lastFace: prefix.lastFace, path: &path, nodes: &local, abort: abort)
                if found {
                    result.store(path.prefix(bound).map { Move(rawValue: $0)! })
                    abort.set()
                    break
                }
                if local > 1 << 20 {
                    nodes.add(local)
                    local = 0
                }
            }
            nodes.add(local)
        }
        return result.value
    }

    /// DFS to exactly `bound` total moves. Writes the solution into
    /// `path` and returns true when found.
    private func depthFirst(
        cube: FastCube, g: Int, bound: Int, lastFace: Int,
        path: inout [Int], nodes: inout Int64, abort: SharedFlag
    ) -> Bool {
        nodes += 1
        if nodes & 0xFFF == 0 && abort.isSet { return false }
        let h = heuristic(of: cube)
        if g + h > bound { return false }
        if h == 0 {
            // PDB distance 0 in all three projections — could still be
            // unsolved overall; verify outright.
            if cube.isSolved { return g == bound }
        }
        if g == bound { return false }
        for move in 0..<18 {
            let face = move / 3
            guard Self.faceAllowed(face, after: lastFace) else { continue }
            path[g] = move
            if depthFirst(
                cube: cube.applying(move), g: g + 1, bound: bound, lastFace: face,
                path: &path, nodes: &nodes, abort: abort)
            {
                return true
            }
        }
        return false
    }

    /// Same canonical ordering as the other solvers: never the same
    /// face twice, opposite faces in one fixed order.
    @inline(__always)
    static func faceAllowed(_ face: Int, after lastFace: Int) -> Bool {
        lastFace < 0 || (face != lastFace && face + 3 != lastFace)
    }
}

// MARK: - Shared search state (lock-based; touched in batches)

final class SharedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Int64 = 0

    func add(_ amount: Int64) {
        lock.lock()
        stored += amount
        lock.unlock()
    }

    func next() -> Int64 {
        lock.lock()
        stored += 1
        defer { lock.unlock() }
        return stored
    }

    var value: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

final class SharedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false

    func set() {
        lock.lock()
        stored = true
        lock.unlock()
    }

    func clear() {
        lock.lock()
        stored = false
        lock.unlock()
    }

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

final class SharedResult: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Move]?

    func store(_ moves: [Move]) {
        lock.lock()
        if stored == nil { stored = moves }
        lock.unlock()
    }

    var value: [Move]? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}
