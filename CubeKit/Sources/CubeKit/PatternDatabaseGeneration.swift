import Foundation

public struct PDBGenerationProgress: Sendable {
    public let tableIndex: Int
    public let tableCount: Int
    public let tableName: String
    public let depth: Int
    public let filledFraction: Double
}

extension PatternDatabaseSet {
    /// Generates every table of `tier` into `directory` (skipping ones
    /// already present), then exports compressed seeds if `seedsDirectory`
    /// is provided. Synchronous and CPU/IO heavy — call from a background
    /// task. Scratch space: one byte per entry in a temp file beside the
    /// output (the OS pages it; peak dirty memory stays bounded).
    public static func generate(
        tier: OptimalTableTier,
        in directory: URL,
        seedsDirectory: URL? = nil,
        progress: @escaping @Sendable (PDBGenerationProgress) -> Void,
        isCancelled: @escaping @Sendable () -> Bool
    ) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let specs = PDBSpec.specs(for: tier)
        for (index, spec) in specs.enumerated() {
            let url = directory.appendingPathComponent(spec.fileName)
            if FileManager.default.fileExists(atPath: url.path) { continue }
            try generateTable(
                spec: spec, to: url,
                report: { depth, fraction in
                    progress(PDBGenerationProgress(
                        tableIndex: index, tableCount: specs.count,
                        tableName: spec.fileName, depth: depth, filledFraction: fraction))
                },
                isCancelled: isCancelled
            )
        }
        if let seedsDirectory {
            try? exportSeeds(tier: tier, from: directory, to: seedsDirectory)
        }
    }

    /// Breadth-first distance fill over the spec's index space, written
    /// as a nibble-packed table file.
    static func generateTable(
        spec: PDBSpec,
        to url: URL,
        report: @escaping @Sendable (Int, Double) -> Void,
        isCancelled: @escaping @Sendable () -> Bool
    ) throws {
        let entryCount = spec.entryCount
        let orientationCount = spec.orientationCount
        let locationCount = spec.locationCount
        let pieceCount = spec.trackedPieces.count
        let radix = spec.orientationRadix
        let digits = spec.orientationDigits
        let slots = spec.slots
        let (destination, orientationDelta) = spec.moveTables()

        let scratchURL = url.appendingPathExtension("scratch")
        defer { try? FileManager.default.removeItem(at: scratchURL) }
        let scratch = try MappedBuffer.createReadWrite(at: scratchURL, size: entryCount)
        let bytes = scratch.bytes

        // 0xFF = unseen.
        memset(bytes, 0xFF, entryCount)
        bytes[spec.solvedIndex] = 0

        // Power weights for orientation digit arithmetic (base `radix`,
        // most significant digit first — matching PDBSpec.index(of:)).
        var digitWeight = [Int](repeating: 1, count: digits)
        for i in stride(from: digits - 2, through: 0, by: -1) {
            digitWeight[i] = digitWeight[i + 1] * radix
        }

        let workerCount = max(1, ProcessInfo.processInfo.activeProcessorCount)
        let chunkSize = (locationCount + workerCount - 1) / workerCount

        var totalFilled = 1
        var depth = 0
        while true {
            if isCancelled() { throw PatternDatabaseError.cancelled }
            let currentDepth = UInt8(depth)
            let filledThisPass = AtomicCounter()

            DispatchQueue.concurrentPerform(iterations: workerCount) { worker in
                let start = worker * chunkSize
                let end = min(start + chunkSize, locationCount)
                guard start < end else { return }

                var decoder = PartialPermutation.SequentialDecoder(
                    slots: slots, pieces: pieceCount, startRank: start)
                var newPositions = [Int](repeating: 0, count: pieceCount)
                var moveLocBase = [Int](repeating: 0, count: 18)
                // Radix 2: the whole orientation transform is one XOR.
                var moveXorMask = [Int](repeating: 0, count: 18)
                // Radix 3: per-move digit deltas, flattened [move*digits+i].
                var moveDigitDelta = [Int](repeating: 0, count: 18 * digits)
                var filled = 0

                for locRank in start..<end {
                    let base = locRank * orientationCount
                    var movesPrepared = false

                    for orientation in 0..<orientationCount
                    where bytes[base + orientation] == currentDepth {
                        if !movesPrepared {
                            movesPrepared = true
                            // Hoist per-move transforms out of the
                            // orientation loop: they depend only on the
                            // piece positions, not the orientations.
                            for move in 0..<18 {
                                let tableBase = move * slots
                                if radix == 2 {
                                    var mask = 0
                                    for i in 0..<pieceCount {
                                        let from = decoder.positions[i]
                                        newPositions[i] = Int(destination[tableBase + from])
                                        mask += Int(orientationDelta[tableBase + from])
                                            * digitWeight[i]
                                    }
                                    moveXorMask[move] = mask
                                } else {
                                    for i in 0..<pieceCount {
                                        let from = decoder.positions[i]
                                        newPositions[i] = Int(destination[tableBase + from])
                                        if i < digits {
                                            moveDigitDelta[move * digits + i] =
                                                Int(orientationDelta[tableBase + from])
                                        }
                                    }
                                }
                                moveLocBase[move] = PartialPermutation.rank(
                                    newPositions, slots: slots) * orientationCount
                            }
                        }
                        if radix == 2 {
                            for move in 0..<18 {
                                let target = moveLocBase[move]
                                    + (orientation ^ moveXorMask[move])
                                if bytes[target] == 0xFF {
                                    bytes[target] = currentDepth + 1
                                    filled += 1
                                }
                            }
                        } else {
                            for move in 0..<18 {
                                var newOrientation = 0
                                var remaining = orientation
                                for i in 0..<digits {
                                    let digit = remaining / digitWeight[i]
                                    remaining -= digit * digitWeight[i]
                                    let moved = (digit + moveDigitDelta[move * digits + i]) % radix
                                    newOrientation += moved * digitWeight[i]
                                }
                                let target = moveLocBase[move] + newOrientation
                                if bytes[target] == 0xFF {
                                    bytes[target] = currentDepth + 1
                                    filled += 1
                                }
                            }
                        }
                    }
                    _ = decoder.advance()
                }
                filledThisPass.add(filled)
            }

            // Workers may double-count an entry both filled in the same
            // pass (the same-value write race is benign, the count is
            // approximate) — good enough for termination and progress.
            let newlyFilled = filledThisPass.value
            if newlyFilled == 0 { break }
            totalFilled = min(totalFilled + newlyFilled, entryCount)
            depth += 1
            report(depth, Double(totalFilled) / Double(entryCount))
        }

        // Exact completeness check: every state must be reachable;
        // anything unseen means the spec or move tables are wrong.
        let unreachable = AtomicCounter()
        DispatchQueue.concurrentPerform(iterations: workerCount) { worker in
            let chunk = (entryCount + workerCount - 1) / workerCount
            let start = worker * chunk
            let end = min(start + chunk, entryCount)
            var missing = 0
            for index in start..<end where bytes[index] == 0xFF {
                missing += 1
            }
            unreachable.add(missing)
        }
        guard unreachable.value == 0 else {
            throw PatternDatabaseError.corruptTable(
                "\(spec.fileName): \(unreachable.value) unreachable entries")
        }

        // Pack to the nibble file.
        let packedURL = url.appendingPathExtension("partial")
        let packedSize = PatternDatabase.headerSize + (entryCount + 1) / 2
        let packed = try MappedBuffer.createReadWrite(at: packedURL, size: packedSize)
        PatternDatabase.writeHeader(into: packed.bytes)
        let packedBytes = packed.bytes + PatternDatabase.headerSize
        DispatchQueue.concurrentPerform(iterations: workerCount) { worker in
            let pairCount = (entryCount + 1) / 2
            let chunk = (pairCount + workerCount - 1) / workerCount
            let start = worker * chunk
            let end = min(start + chunk, pairCount)
            for pair in start..<end {
                let low = bytes[pair * 2]
                let high = pair * 2 + 1 < entryCount ? bytes[pair * 2 + 1] : 0
                packedBytes[pair] = (high << 4) | low
            }
        }
        msync(packed.pointer, packedSize, MS_SYNC)
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: packedURL, to: url)
    }
}

/// Minimal lock-based counter (exact totals matter only per pass; the
/// hot path increments a local and adds once per worker).
final class AtomicCounter: @unchecked Sendable {
    private var lock = NSLock()
    private var stored = 0

    func add(_ amount: Int) {
        lock.lock()
        stored += amount
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}
