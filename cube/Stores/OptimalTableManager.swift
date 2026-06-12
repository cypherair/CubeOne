import CubeKit
import Foundation
import SwiftUI

/// A thread-safe cancellation token shared with background work.
nonisolated final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

/// Tracks and manages the optimal solver's pattern-database tiers:
/// installed in Application Support, seeded in the app bundle, or
/// generated on demand.
@Observable
final class OptimalTableManager {
    enum TierStatus: Equatable {
        /// Not on disk; `seedAvailable` says whether the app bundle can
        /// install it without generating.
        case absent(seedAvailable: Bool)
        case installingSeed(progress: Double)
        case generating(tableIndex: Int, tableCount: Int, fraction: Double)
        case installed(bytes: Int64)
    }

    private(set) var status: [OptimalTableTier: TierStatus] = [:]
    private(set) var busyTier: OptimalTableTier?
    private var cancelToken: CancelToken?

    private let directory = AppModel.supportDirectory
    private var bundleSeedsDirectory: URL? { Bundle.main.resourceURL }

    init() {
        refresh()
    }

    func refresh() {
        for tier in OptimalTableTier.allCases {
            if busyTier == tier { continue }
            if let bytes = PatternDatabaseSet.installedByteSize(tier: tier, in: directory) {
                status[tier] = .installed(bytes: bytes)
            } else {
                let seeded = bundleSeedsDirectory.map {
                    PatternDatabaseSet.seedsAvailable(tier: tier, in: $0)
                } ?? false
                status[tier] = .absent(seedAvailable: seeded)
            }
        }
    }

    var bestReadyTier: OptimalTableTier? {
        OptimalTableTier.allCases.sorted(by: >).first { tier in
            if case .installed = status[tier] { return true }
            return false
        }
    }

    /// Installs from a bundle seed when available, otherwise generates.
    func prepare(_ tier: OptimalTableTier) {
        guard busyTier == nil else { return }
        busyTier = tier
        let token = CancelToken()
        cancelToken = token
        let directory = directory
        let seeds = bundleSeedsDirectory
        let seedAvailable = seeds.map {
            PatternDatabaseSet.seedsAvailable(tier: tier, in: $0)
        } ?? false

        if seedAvailable {
            status[tier] = .installingSeed(progress: 0)
        } else {
            status[tier] = .generating(tableIndex: 0, tableCount: 3, fraction: 0)
        }

        let seedsExport = Self.seedsExportDirectory
        Task.detached(priority: .userInitiated) {
            do {
                if seedAvailable, let seeds {
                    _ = try PatternDatabaseSet.installSeeds(
                        tier: tier, from: seeds, into: directory
                    ) { fraction in
                        Task { @MainActor in
                            guard self.busyTier == tier else { return }
                            self.status[tier] = .installingSeed(progress: fraction)
                        }
                    }
                } else {
                    try PatternDatabaseSet.generate(
                        tier: tier, in: directory,
                        seedsDirectory: seedsExport,
                        progress: { progress in
                            Task { @MainActor in
                                guard self.busyTier == tier else { return }
                                self.status[tier] = .generating(
                                    tableIndex: progress.tableIndex,
                                    tableCount: progress.tableCount,
                                    fraction: progress.filledFraction)
                            }
                        },
                        isCancelled: { token.isCancelled })
                }
            } catch {
                print("Table preparation failed: \(error)")
            }
            await MainActor.run {
                self.busyTier = nil
                self.cancelToken = nil
                self.refresh()
            }
        }
    }

    func cancelPreparation() {
        cancelToken?.cancel()
    }

    func delete(_ tier: OptimalTableTier) {
        guard busyTier == nil else { return }
        PatternDatabaseSet.deleteTables(tier: tier, in: directory)
        refresh()
    }

    /// Generated tables are also exported as compressed seeds next to
    /// the repo so the build phase can bundle them (development builds
    /// only — the path exists when running from Xcode on this machine).
    static var seedsExportDirectory: URL? {
        // Application Support/CubeOne/Seeds — the build phase copies
        // from the repo's Seeds/, which the developer syncs by hand or
        // via the documented recipe; exporting here keeps the app
        // sandbox-safe.
        AppModel.supportDirectory.appendingPathComponent("Seeds", isDirectory: true)
    }

    func openDatabases(tier: OptimalTableTier) throws -> PatternDatabaseSet {
        try PatternDatabaseSet(tier: tier, directory: directory)
    }
}
