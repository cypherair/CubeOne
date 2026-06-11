import SwiftUI

/// The Stats tab: personal records for timed solves.
struct StatsView: View {
    let stats: StatsStore

    var body: some View {
        NavigationStack {
            Group {
                if stats.records.isEmpty {
                    ContentUnavailableView(
                        "No timed solves yet",
                        systemImage: "stopwatch",
                        description: Text("Start a timer session and solve the cube — your times will appear here.")
                    )
                } else {
                    List {
                        Section("Records") {
                            row("Best", stats.best.map { formatSolveDuration($0.duration) } ?? "—")
                            row("Average of 5", stats.averageOfFive.map(formatSolveDuration) ?? "—")
                            row("Solves", "\(stats.records.count)")
                        }
                        Section("Recent") {
                            ForEach(stats.recent) { record in
                                HStack {
                                    Text(formatSolveDuration(record.duration))
                                        .font(.body.monospacedDigit().weight(.medium))
                                    Spacer()
                                    Text("^[\(record.moveCount) move](inflect: true)")
                                        .foregroundStyle(.secondary)
                                    Text(record.date, format: .dateTime.month().day().hour().minute())
                                        .foregroundStyle(.tertiary)
                                        .font(.footnote)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Stats")
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit().weight(.semibold))
        }
    }
}
