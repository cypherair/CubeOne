/// Lexicographic ranking of partial permutations: the positions of k
/// tracked pieces among n slots (all distinct), ranked 0..<P(n,k).
///
/// Used by pattern databases, where an index must enumerate every
/// arrangement of a tracked piece subset compactly.
enum PartialPermutation {
    /// Number of arrangements P(n, k) = n·(n−1)·…·(n−k+1).
    static func count(slots n: Int, pieces k: Int) -> Int {
        var result = 1
        for i in 0..<k { result *= n - i }
        return result
    }

    /// Rank of `positions` (slot of each tracked piece, in piece order).
    static func rank(_ positions: [Int], slots n: Int) -> Int {
        var rank = 0
        var usedMask: UInt32 = 0
        for (i, position) in positions.enumerated() {
            let smallerUsed = (usedMask & ((1 << UInt32(position)) - 1)).nonzeroBitCount
            rank = rank * (n - i) + (position - smallerUsed)
            usedMask |= 1 << UInt32(position)
        }
        return rank
    }

    /// Inverse of `rank`.
    static func unrank(_ rank: Int, slots n: Int, pieces k: Int) -> [Int] {
        // Extract mixed-radix digits (most significant first).
        var digits = [Int](repeating: 0, count: k)
        var r = rank
        for i in stride(from: k - 1, through: 0, by: -1) {
            digits[i] = r % (n - i)
            r /= n - i
        }
        var positions = [Int](repeating: 0, count: k)
        var usedMask: UInt32 = 0
        for i in 0..<k {
            positions[i] = nthUnusedSlot(digits[i], usedMask: usedMask)
            usedMask |= 1 << UInt32(positions[i])
        }
        return positions
    }

    /// The index of the (digit+1)-th clear bit in `usedMask`.
    private static func nthUnusedSlot(_ digit: Int, usedMask: UInt32) -> Int {
        var remaining = digit
        var slot = 0
        while true {
            if usedMask & (1 << UInt32(slot)) == 0 {
                if remaining == 0 { return slot }
                remaining -= 1
            }
            slot += 1
        }
    }

    /// Walks ranks 0, 1, 2, … sequentially, exposing the decoded
    /// positions without paying full unrank cost per step (the last
    /// digit changes every step; earlier digits change geometrically
    /// less often).
    struct SequentialDecoder {
        let slots: Int
        let pieces: Int
        private(set) var positions: [Int]
        private var digits: [Int]

        init(slots: Int, pieces: Int, startRank: Int = 0) {
            self.slots = slots
            self.pieces = pieces
            positions = PartialPermutation.unrank(startRank, slots: slots, pieces: pieces)
            digits = [Int](repeating: 0, count: pieces)
            var r = startRank
            for i in stride(from: pieces - 1, through: 0, by: -1) {
                digits[i] = r % (slots - i)
                r /= slots - i
            }
        }

        /// Advances to the next rank. Returns false past the last rank.
        mutating func advance() -> Bool {
            // Increment the mixed-radix odometer from the least
            // significant digit, then rebuild positions from the first
            // changed digit onward.
            var i = pieces - 1
            while i >= 0 {
                digits[i] += 1
                if digits[i] < slots - i { break }
                digits[i] = 0
                i -= 1
            }
            if i < 0 { return false }
            // Recompute positions[i...] using the used-mask of the
            // unchanged prefix.
            var usedMask: UInt32 = 0
            for j in 0..<i {
                usedMask |= 1 << UInt32(positions[j])
            }
            for j in i..<pieces {
                positions[j] = PartialPermutation.nthUnusedSlot(digits[j], usedMask: usedMask)
                usedMask |= 1 << UInt32(positions[j])
            }
            return true
        }
    }
}
