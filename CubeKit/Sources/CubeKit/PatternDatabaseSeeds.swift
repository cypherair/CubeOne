import Compression
import Foundation

extension PatternDatabaseSet {
    public static func seedFileName(for tableFileName: String) -> String {
        tableFileName + ".lzfse"
    }

    public static func seedFileNames(tier: OptimalTableTier) -> [String] {
        tableFileNames(tier: tier).map(seedFileName(for:))
    }

    /// Compresses installed tables into `seedsDirectory` (used by the
    /// build phase to bundle them into the app).
    public static func exportSeeds(
        tier: OptimalTableTier, from directory: URL, to seedsDirectory: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: seedsDirectory, withIntermediateDirectories: true)
        for name in tableFileNames(tier: tier) {
            let source = directory.appendingPathComponent(name)
            let target = seedsDirectory.appendingPathComponent(seedFileName(for: name))
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            if FileManager.default.fileExists(atPath: target.path) { continue }
            try filter(from: source, to: target, operation: .compress)
        }
    }

    /// True when every table of the tier has a seed in the directory
    /// (typically the app bundle's resources).
    public static func seedsAvailable(tier: OptimalTableTier, in seedsDirectory: URL) -> Bool {
        seedFileNames(tier: tier).allSatisfy { name in
            FileManager.default.fileExists(
                atPath: seedsDirectory.appendingPathComponent(name).path)
        }
    }

    /// Decompresses bundled seeds into the working directory. Returns
    /// false if seeds are missing.
    public static func installSeeds(
        tier: OptimalTableTier,
        from seedsDirectory: URL,
        into directory: URL,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) throws -> Bool {
        guard seedsAvailable(tier: tier, in: seedsDirectory) else { return false }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let names = tableFileNames(tier: tier)
        for (index, name) in names.enumerated() {
            let target = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: target.path) {
                progress(Double(index + 1) / Double(names.count))
                continue
            }
            let seed = seedsDirectory.appendingPathComponent(seedFileName(for: name))
            let partial = target.appendingPathExtension("partial")
            try filter(from: seed, to: partial, operation: .decompress)
            try FileManager.default.moveItem(at: partial, to: target)
            progress(Double(index + 1) / Double(names.count))
        }
        return true
    }

    static func compressForTesting(from source: URL, to target: URL) throws {
        try filter(from: source, to: target, operation: .compress)
    }

    static func decompressForTesting(from source: URL, to target: URL) throws {
        try filter(from: source, to: target, operation: .decompress)
    }

    /// Streams a file through LZFSE without loading it into memory.
    private static func filter(
        from source: URL, to target: URL, operation: FilterOperation
    ) throws {
        try? FileManager.default.removeItem(at: target)
        FileManager.default.createFile(atPath: target.path, contents: nil)
        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: target)
        defer {
            try? input.close()
            try? output.close()
        }
        let chunkSize = 8 << 20
        let outputFilter = try OutputFilter(operation, using: .lzfse) { data in
            if let data { output.write(data) }
        }
        while true {
            let chunk = try input.read(upToCount: chunkSize) ?? Data()
            try outputFilter.write(chunk)
            if chunk.count < chunkSize { break }
        }
        try outputFilter.finalize()
    }
}
