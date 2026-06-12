import Foundation

/// Shared builders for coordinate move tables and breadth-first distance
/// tables, used by both the Kociemba and Thistlethwaite table sets.
enum TableBuilder {
    static func permutationApplying(
        _ permutation: [Int], _ movePermutation: [Int], times: Int
    ) -> [Int] {
        var result = permutation
        for _ in 0..<times {
            var next = result
            for i in 0..<result.count { next[i] = result[movePermutation[i]] }
            result = next
        }
        return result
    }

    /// Move table for an orientation coordinate, indexed
    /// `[coordinate * 18 + move]` over all eighteen moves.
    static func orientationTable(
        count: Int, pieceCount: Int, modulus: Int,
        decode: (Int) -> [Int], encode: ([Int]) -> Int,
        movePermutation: (Int) -> [Int], moveOrientation: (Int) -> [Int]
    ) -> [UInt16] {
        var table = [UInt16](repeating: 0, count: count * 18)
        for coordinate in 0..<count {
            let orientations = decode(coordinate)
            for move in 0..<18 {
                let face = move / 3
                let permutation = movePermutation(face)
                let orientation = moveOrientation(face)
                var current = orientations
                for _ in 0..<(move % 3 + 1) {
                    var next = current
                    for i in 0..<pieceCount {
                        next[i] = (current[permutation[i]] + orientation[i]) % modulus
                    }
                    current = next
                }
                table[coordinate * 18 + move] = UInt16(encode(current))
            }
        }
        return table
    }

    /// Move table for a (sub-)permutation coordinate, indexed
    /// `[coordinate * moves.count + moveIndex]` over the given `Move` raw
    /// values. `project` extracts the ranked sub-permutation from a full
    /// arrangement; `embed` rebuilds a representative full arrangement.
    static func permutationTable(
        count: Int, pieceCount: Int, moves: [Int],
        movePermutation: (Int) -> [Int],
        project: ([Int]) -> [Int], embed: ([Int]) -> [Int]
    ) -> [UInt16] {
        var table = [UInt16](repeating: 0, count: count * moves.count)
        for coordinate in 0..<count {
            let full = embed(Coordinates.unrankPermutation(coordinate, count: pieceCount))
            for (index, moveValue) in moves.enumerated() {
                let moved = permutationApplying(
                    full, movePermutation(moveValue / 3), times: moveValue % 3 + 1)
                table[coordinate * moves.count + index] =
                    UInt16(Coordinates.rankPermutation(project(moved)))
            }
        }
        return table
    }

    /// Move table for an occupancy coordinate: the colex rank of which of
    /// the first `slotCount` slots (of a `totalSlots`-piece permutation)
    /// hold the `markerCount` tracked pieces. Representatives place marker
    /// values (≥ `totalSlots - markerCount`) at the occupied slots; every
    /// allowed move must keep markers within the first `slotCount` slots.
    static func occupancyTable(
        slotCount: Int, markerCount: Int, totalSlots: Int, moves: [Int],
        movePermutation: (Int) -> [Int]
    ) -> [UInt16] {
        let stateCount = Coordinates.binomial[slotCount][markerCount]
        let markerFloor = totalSlots - markerCount
        var table = [UInt16](repeating: 0, count: stateCount * moves.count)
        for coordinate in 0..<stateCount {
            let positions = Set(occupiedSlots(
                forRank: coordinate, slots: slotCount, count: markerCount))
            var permutation = [Int](repeating: 0, count: totalSlots)
            var nextMarker = markerFloor
            var nextFiller = 0
            for slot in 0..<totalSlots {
                if positions.contains(slot) {
                    permutation[slot] = nextMarker
                    nextMarker += 1
                } else {
                    permutation[slot] = nextFiller
                    nextFiller += 1
                }
            }
            for (index, moveValue) in moves.enumerated() {
                let moved = permutationApplying(
                    permutation, movePermutation(moveValue / 3), times: moveValue % 3 + 1)
                var rank = 0
                var found = 0
                for slot in 0..<slotCount where moved[slot] >= markerFloor {
                    found += 1
                    rank += Coordinates.binomial[slot][found]
                }
                table[coordinate * moves.count + index] = UInt16(rank)
            }
        }
        return table
    }

    /// The occupied slot list (ascending) for a colex occupancy rank.
    static func occupiedSlots(forRank rank: Int, slots: Int, count: Int) -> [Int] {
        var positions: [Int] = []
        var r = rank
        for i in stride(from: count, through: 1, by: -1) {
            var p = slots - 1
            while Coordinates.binomial[p][i] > r { p -= 1 }
            positions.append(p)
            r -= Coordinates.binomial[p][i]
        }
        return positions.reversed()
    }

    /// Exact distances from the `starts` set to every reachable state.
    /// Unreached states stay -1; pass `requireFullCoverage: false` for
    /// spaces that are legitimately only partially reachable.
    static func breadthFirstDistances(
        stateCount: Int, moveCount: Int, starts: [Int],
        requireFullCoverage: Bool = true,
        neighbor: (Int, Int) -> Int
    ) -> [Int8] {
        var distances = [Int8](repeating: -1, count: stateCount)
        var queue = [Int32]()
        queue.reserveCapacity(stateCount)
        for start in starts where distances[start] < 0 {
            distances[start] = 0
            queue.append(Int32(start))
        }
        var head = 0
        while head < queue.count {
            let state = Int(queue[head])
            head += 1
            let next = distances[state] + 1
            for move in 0..<moveCount {
                let target = neighbor(state, move)
                if distances[target] < 0 {
                    distances[target] = next
                    queue.append(Int32(target))
                }
            }
        }
        assert(
            !requireFullCoverage || !distances.contains(-1),
            "pruning table has unreachable states")
        return distances
    }
}
