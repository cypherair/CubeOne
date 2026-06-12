import Foundation
@testable import CubeKit

/// Tables are expensive to generate in debug builds, so share one
/// instance across suites and cache it on disk between test runs.
enum TestTables {
    static let shared: SolverTables = {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CubeKitTestTables")
        return (try? SolverTables.cached(in: directory)) ?? SolverTables.generate()
    }()

    static let solver = KociembaSolver(tables: shared)

    static let thistlethwaite: ThistlethwaiteTables = {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CubeKitTestThistlethwaiteTables")
        return (try? ThistlethwaiteTables.cached(in: directory))
            ?? ThistlethwaiteTables.generate()
    }()
}
