/// Integer "coordinates" that project a `CubeState` onto the small
/// subspaces the two-phase solver searches over.
///
/// Phase 1 coordinates (defined for any state):
/// - twist:  corner orientations, 3⁷ = 2187 values (solved = 0)
/// - flip:   edge orientations, 2¹¹ = 2048 values (solved = 0)
/// - slice:  which four slots hold the E-slice edges (FR, FL, BL, BR),
///           C(12,4) = 495 values (solved = 494 in colex ranking)
///
/// Phase 2 coordinates (defined only inside G1 = ⟨U, D, R2, L2, F2, B2⟩):
/// - cornerPermutation: 8! = 40320 (solved = 0)
/// - udEdgePermutation: permutation of the eight U/D edges, 8! = 40320
/// - sliceEdgePermutation: permutation of the four slice edges, 4! = 24
enum Coordinates {
    static let twistCount = 2187
    static let flipCount = 2048
    static let sliceCount = 495
    static let cornerPermutationCount = 40320
    static let udEdgePermutationCount = 40320
    static let sliceEdgePermutationCount = 24

    /// Slice coordinate of the solved cube (slice edges in slots 8...11).
    static let solvedSlice = 494

    // MARK: Orientation coordinates

    static func twist(of state: CubeState) -> Int {
        var value = 0
        for i in 0..<7 { value = value * 3 + state.cornerOrientation[i] }
        return value
    }

    static func cornerOrientations(forTwist twist: Int) -> [Int] {
        var orientations = [Int](repeating: 0, count: 8)
        var t = twist
        for i in stride(from: 6, through: 0, by: -1) {
            orientations[i] = t % 3
            t /= 3
        }
        orientations[7] = (3 - orientations[0..<7].reduce(0, +) % 3) % 3
        return orientations
    }

    static func flip(of state: CubeState) -> Int {
        var value = 0
        for i in 0..<11 { value = value * 2 + state.edgeOrientation[i] }
        return value
    }

    static func edgeOrientations(forFlip flip: Int) -> [Int] {
        var orientations = [Int](repeating: 0, count: 12)
        var f = flip
        for i in stride(from: 10, through: 0, by: -1) {
            orientations[i] = f % 2
            f /= 2
        }
        orientations[11] = orientations[0..<11].reduce(0, +) % 2
        return orientations
    }

    // MARK: Slice location coordinate

    /// C(n, k) for n ≤ 12.
    static let binomial: [[Int]] = {
        var table = [[Int]](repeating: [Int](repeating: 0, count: 5), count: 13)
        for n in 0...12 {
            table[n][0] = 1
            for k in 1...4 where k <= n {
                table[n][k] = table[n - 1][k - 1] + (n - 1 >= k ? table[n - 1][k] : 0)
            }
        }
        return table
    }()

    static func slice(of state: CubeState) -> Int {
        var rank = 0
        var found = 0
        for slot in 0..<12 where state.edgePermutation[slot] >= 8 {
            found += 1
            rank += binomial[slot][found]
        }
        return rank
    }

    /// The four slots holding slice edges for a given slice coordinate,
    /// ascending.
    static func slicePositions(forSlice slice: Int) -> [Int] {
        var positions: [Int] = []
        var r = slice
        for i in stride(from: 4, through: 1, by: -1) {
            var p = 11
            while binomial[p][i] > r { p -= 1 }
            positions.append(p)
            r -= binomial[p][i]
        }
        return positions.reversed()
    }

    // MARK: Permutation coordinates (Lehmer rank)

    static func rankPermutation(_ permutation: [Int]) -> Int {
        var rank = 0
        for i in 0..<permutation.count {
            var smaller = 0
            for j in (i + 1)..<permutation.count where permutation[j] < permutation[i] {
                smaller += 1
            }
            rank = rank * (permutation.count - i) + smaller
        }
        return rank
    }

    static func unrankPermutation(_ rank: Int, count: Int) -> [Int] {
        var available = Array(0..<count)
        var result: [Int] = []
        var r = rank
        var factorial = (1..<Swift.max(count, 2)).reduce(1, *)
        for i in 0..<count {
            result.append(available.remove(at: r / factorial))
            r %= factorial
            let remaining = count - 1 - i
            if remaining > 1 { factorial /= remaining }
        }
        return result
    }

    // MARK: Coordinates of a state

    static func cornerPermutation(of state: CubeState) -> Int {
        rankPermutation(state.cornerPermutation)
    }

    /// Requires the state to be in G1 (all U/D edges in U/D slots).
    static func udEdgePermutation(of state: CubeState) -> Int {
        rankPermutation(Array(state.edgePermutation[0..<8]))
    }

    /// Requires the state to be in G1 (slice edges in slice slots).
    static func sliceEdgePermutation(of state: CubeState) -> Int {
        rankPermutation(state.edgePermutation[8..<12].map { $0 - 8 })
    }
}
