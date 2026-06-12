import CubeKit
import Foundation

// Headless pattern-database baking, for CI or scripted local use.
// Usage: cubekit-bake <7|8> <output-directory>
// Writes tables to <out>/tables and compressed seeds to <out>/seeds.

let arguments = CommandLine.arguments
guard arguments.count == 3,
      let tierValue = Int(arguments[1]),
      let tier = OptimalTableTier(rawValue: tierValue)
else {
    print("usage: cubekit-bake <7|8> <output-directory>")
    exit(64)
}

let output = URL(fileURLWithPath: arguments[2], isDirectory: true)
let tables = output.appendingPathComponent("tables", isDirectory: true)
let seeds = output.appendingPathComponent("seeds", isDirectory: true)

let clock = ContinuousClock()
let started = clock.now
print("Baking \(tier.rawValue)-edge tier into \(tables.path)")

do {
    try PatternDatabaseSet.generate(
        tier: tier, in: tables, seedsDirectory: seeds,
        progress: { progress in
            let percent = Int(progress.filledFraction * 100)
            print("[\(progress.tableIndex + 1)/\(progress.tableCount)] "
                + "\(progress.tableName) depth \(progress.depth) — \(percent)% "
                + "(\(clock.now - started) elapsed)")
            fflush(stdout)
        },
        isCancelled: { false }
    )
} catch {
    print("Bake failed: \(error)")
    exit(1)
}

print("Done in \(clock.now - started). Seeds in \(seeds.path)")
