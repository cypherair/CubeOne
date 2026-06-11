import Foundation

/// Timed-solve records, persisted as JSON in Application Support.
@Observable
final class StatsStore {
    struct SolveRecord: Codable, Identifiable, Sendable {
        let id: UUID
        let date: Date
        let duration: TimeInterval
        let moveCount: Int
    }

    private(set) var records: [SolveRecord] = []
    private let fileURL: URL

    init(directory: URL = AppModel.supportDirectory) {
        fileURL = directory.appendingPathComponent("stats.json")
        load()
    }

    var best: SolveRecord? {
        records.min { $0.duration < $1.duration }
    }

    /// WCA-style average of the last five solves: drop best and worst,
    /// mean of the middle three.
    var averageOfFive: TimeInterval? {
        guard records.count >= 5 else { return nil }
        let durations = records.suffix(5).map(\.duration).sorted()
        return durations[1...3].reduce(0, +) / 3
    }

    var recent: [SolveRecord] { records.suffix(10).reversed() }

    @discardableResult
    func add(duration: TimeInterval, moveCount: Int) -> SolveRecord {
        let record = SolveRecord(
            id: UUID(), date: .now, duration: duration, moveCount: moveCount)
        records.append(record)
        save()
        return record
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([SolveRecord].self, from: data)
        else { return }
        records = decoded
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(records)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save stats: \(error)")
        }
    }
}

func formatSolveDuration(_ duration: TimeInterval) -> String {
    if duration >= 60 {
        let minutes = Int(duration) / 60
        let seconds = duration - Double(minutes * 60)
        return String(format: "%d:%05.2f", minutes, seconds)
    }
    return String(format: "%.2f", duration)
}
