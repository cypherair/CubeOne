import Foundation

/// Pattern-database tier for the optimal solver: how many edges each of
/// the two edge tables tracks. Bigger tracks ⇒ stronger heuristic ⇒
/// faster searches, at the cost of table size.
public enum OptimalTableTier: Int, CaseIterable, Sendable, Codable, Comparable {
    case sevenEdge = 7
    case eightEdge = 8

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var edgeSubsetSize: Int { rawValue }

    /// Approximate bytes of the installed (uncompressed) tables.
    public var installedByteEstimate: Int64 {
        let edgeEntries = Int64(PartialPermutation.count(slots: 12, pieces: edgeSubsetSize))
            * Int64(1 << edgeSubsetSize)
        return edgeEntries + 44_089_920  // two edge tables (nibbles) + corner table
    }
}

/// Describes one pattern database: the tracked pieces, the orientation
/// encoding, and the per-move transforms of tracked positions.
struct PDBSpec: Sendable {
    enum Kind: Sendable {
        case corners
        /// Tracked edge pieces, in tracking order.
        case edges([Int])
    }

    let kind: Kind
    let fileName: String

    var slots: Int {
        switch kind {
        case .corners: 8
        case .edges: 12
        }
    }

    var trackedPieces: [Int] {
        switch kind {
        case .corners: Array(0..<8)
        case .edges(let subset): subset
        }
    }

    var orientationRadix: Int {
        switch kind {
        case .corners: 3
        case .edges: 2
        }
    }

    /// Corner orientations have a fixed total (mod 3), so the last
    /// tracked piece's orientation is derived rather than stored.
    var orientationDigits: Int {
        switch kind {
        case .corners: 7
        case .edges(let subset): subset.count
        }
    }

    var orientationCount: Int {
        var result = 1
        for _ in 0..<orientationDigits { result *= orientationRadix }
        return result
    }

    var locationCount: Int {
        PartialPermutation.count(slots: slots, pieces: trackedPieces.count)
    }

    var entryCount: Int { locationCount * orientationCount }

    /// destination[move * slots + slot] = slot a piece moves to;
    /// orientationDelta[move * slots + slot] = orientation added.
    /// Derived from `CubeState.basicMoves`.
    func moveTables() -> (destination: [Int8], orientationDelta: [Int8]) {
        var destination = [Int8](repeating: 0, count: 18 * slots)
        var orientationDelta = [Int8](repeating: 0, count: 18 * slots)
        for move in Move.allCases {
            let state = CubeState.solved.applying(move)
            let permutation: [Int]
            let orientation: [Int]
            switch kind {
            case .corners:
                permutation = state.cornerPermutation
                orientation = state.cornerOrientation
            case .edges:
                permutation = state.edgePermutation
                orientation = state.edgeOrientation
            }
            for slot in 0..<slots {
                // The piece that was at `from` is now at `slot`.
                let from = permutation[slot]
                destination[move.rawValue * slots + from] = Int8(slot)
                orientationDelta[move.rawValue * slots + from] = Int8(orientation[slot])
            }
        }
        return (destination, orientationDelta)
    }

    // MARK: Indexing

    /// Index of a full cube state's projection onto this database.
    func index(of state: CubeState) -> Int {
        let permutation: [Int]
        let orientationBySlot: [Int]
        switch kind {
        case .corners:
            permutation = state.cornerPermutation
            orientationBySlot = state.cornerOrientation
        case .edges:
            permutation = state.edgePermutation
            orientationBySlot = state.edgeOrientation
        }
        var positions = [Int](repeating: 0, count: trackedPieces.count)
        for (i, piece) in trackedPieces.enumerated() {
            positions[i] = permutation.firstIndex(of: piece)!
        }
        var orientationValue = 0
        for i in 0..<orientationDigits {
            orientationValue = orientationValue * orientationRadix
                + orientationBySlot[positions[i]]
        }
        return PartialPermutation.rank(positions, slots: slots) * orientationCount
            + orientationValue
    }

    /// Index of the solved projection.
    var solvedIndex: Int {
        // In a solved cube every tracked piece sits in its own slot with
        // orientation zero.
        PartialPermutation.rank(trackedPieces, slots: slots) * orientationCount
    }

    static func specs(for tier: OptimalTableTier) -> [PDBSpec] {
        let k = tier.edgeSubsetSize
        return [
            PDBSpec(kind: .corners, fileName: "optimal-corners.pdb"),
            PDBSpec(kind: .edges(Array(0..<k)), fileName: "optimal-edges-a\(k).pdb"),
            PDBSpec(kind: .edges(Array((12 - k)..<12)), fileName: "optimal-edges-b\(k).pdb"),
        ]
    }
}

/// A memory-mapped file region. Read-only for lookups; writable shared
/// mapping for generation scratch (dirty pages managed by the OS).
final class MappedBuffer: @unchecked Sendable {
    let pointer: UnsafeMutableRawPointer
    let count: Int
    private let fileDescriptor: Int32

    private init(pointer: UnsafeMutableRawPointer, count: Int, fileDescriptor: Int32) {
        self.pointer = pointer
        self.count = count
        self.fileDescriptor = fileDescriptor
    }

    static func createReadWrite(at url: URL, size: Int) throws -> MappedBuffer {
        let fd = Darwin.open(url.path, O_RDWR | O_CREAT | O_TRUNC, 0o644)
        guard fd >= 0 else { throw PatternDatabaseError.io("create \(url.lastPathComponent)") }
        guard ftruncate(fd, off_t(size)) == 0 else {
            close(fd)
            throw PatternDatabaseError.io("resize \(url.lastPathComponent)")
        }
        guard let pointer = mmap(nil, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0),
              pointer != MAP_FAILED
        else {
            close(fd)
            throw PatternDatabaseError.io("map \(url.lastPathComponent)")
        }
        return MappedBuffer(pointer: pointer, count: size, fileDescriptor: fd)
    }

    static func openReadOnly(at url: URL) throws -> MappedBuffer {
        let fd = Darwin.open(url.path, O_RDONLY)
        guard fd >= 0 else { throw PatternDatabaseError.io("open \(url.lastPathComponent)") }
        let size = Int(lseek(fd, 0, SEEK_END))
        guard size > 0,
              let pointer = mmap(nil, size, PROT_READ, MAP_SHARED, fd, 0),
              pointer != MAP_FAILED
        else {
            close(fd)
            throw PatternDatabaseError.io("map \(url.lastPathComponent)")
        }
        return MappedBuffer(pointer: pointer, count: size, fileDescriptor: fd)
    }

    var bytes: UnsafeMutablePointer<UInt8> {
        pointer.assumingMemoryBound(to: UInt8.self)
    }

    deinit {
        munmap(pointer, count)
        close(fileDescriptor)
    }
}

public enum PatternDatabaseError: Error {
    case io(String)
    case corruptTable(String)
    case cancelled
}

/// One nibble-packed distance table, memory-mapped.
final class PatternDatabase: @unchecked Sendable {
    static let headerSize = 32
    static let magic: UInt32 = 0x434B_5044  // "CKPD"
    static let version: UInt32 = 1

    let spec: PDBSpec
    private let buffer: MappedBuffer

    init(spec: PDBSpec, directory: URL) throws {
        self.spec = spec
        let url = directory.appendingPathComponent(spec.fileName)
        buffer = try MappedBuffer.openReadOnly(at: url)
        guard buffer.count == Self.headerSize + (spec.entryCount + 1) / 2,
              Self.readHeaderField(buffer, 0) == Self.magic,
              Self.readHeaderField(buffer, 1) == Self.version
        else { throw PatternDatabaseError.corruptTable(spec.fileName) }
    }

    private static func readHeaderField(_ buffer: MappedBuffer, _ index: Int) -> UInt32 {
        buffer.pointer.loadUnaligned(fromByteOffset: index * 4, as: UInt32.self)
    }

    static func writeHeader(into buffer: UnsafeMutablePointer<UInt8>) {
        withUnsafeBytes(of: magic) { bytes in
            for i in 0..<4 { buffer[i] = bytes[i] }
        }
        withUnsafeBytes(of: version) { bytes in
            for i in 0..<4 { buffer[4 + i] = bytes[i] }
        }
    }

    @inline(__always)
    func distance(atIndex index: Int) -> Int {
        let byte = buffer.bytes[Self.headerSize + (index >> 1)]
        return Int((index & 1) == 0 ? byte & 0xF : byte >> 4)
    }

    /// Base pointer of the nibble data, for hot-path lookups.
    var nibbleBase: UnsafePointer<UInt8> {
        UnsafePointer(buffer.bytes + Self.headerSize)
    }

    func distance(of state: CubeState) -> Int {
        distance(atIndex: spec.index(of: state))
    }
}

/// The corner + two edge tables of one tier, with the max-of-three
/// admissible heuristic.
public final class PatternDatabaseSet: @unchecked Sendable {
    public let tier: OptimalTableTier
    let tables: [PatternDatabase]

    public static func tableFileNames(tier: OptimalTableTier) -> [String] {
        PDBSpec.specs(for: tier).map(\.fileName)
    }

    public static func isInstalled(tier: OptimalTableTier, in directory: URL) -> Bool {
        PDBSpec.specs(for: tier).allSatisfy { spec in
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(spec.fileName).path)
        }
    }

    public static func bestInstalledTier(in directory: URL) -> OptimalTableTier? {
        OptimalTableTier.allCases.sorted(by: >).first { isInstalled(tier: $0, in: directory) }
    }

    public static func installedByteSize(tier: OptimalTableTier, in directory: URL) -> Int64? {
        guard isInstalled(tier: tier, in: directory) else { return nil }
        return PDBSpec.specs(for: tier).reduce(Int64(0)) { total, spec in
            let path = directory.appendingPathComponent(spec.fileName).path
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            return total + ((attributes?[.size] as? Int64) ?? 0)
        }
    }

    public static func deleteTables(tier: OptimalTableTier, in directory: URL) {
        for spec in PDBSpec.specs(for: tier) where spec.kind.isTierSpecific || !otherTierInstalled(tier, directory) {
            try? FileManager.default.removeItem(
                at: directory.appendingPathComponent(spec.fileName))
        }
    }

    private static func otherTierInstalled(_ tier: OptimalTableTier, _ directory: URL) -> Bool {
        OptimalTableTier.allCases.contains { other in
            other != tier && isInstalled(tier: other, in: directory)
        }
    }

    public init(tier: OptimalTableTier, directory: URL) throws {
        self.tier = tier
        tables = try PDBSpec.specs(for: tier).map { spec in
            try PatternDatabase(spec: spec, directory: directory)
        }
    }

    /// For tests: a set over arbitrary tables (e.g. tiny tiers).
    init(tables: [PatternDatabase], tier: OptimalTableTier) {
        self.tier = tier
        self.tables = tables
    }

    /// Lower bound on the number of moves needed to solve `state`.
    public func heuristic(for state: CubeState) -> Int {
        tables.reduce(0) { max($0, $1.distance(of: state)) }
    }
}

extension PDBSpec.Kind {
    /// The corner table is shared by every tier; edge tables are not.
    var isTierSpecific: Bool {
        if case .edges = self { return true }
        return false
    }
}
