import SwiftUI

/// Live progress of a running optimal (proven-shortest) search.
struct OptimalSearchPanel: View {
    let model: AppModel
    let session: AppModel.OptimalSearchSession

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Searching for the shortest solution")
                    .font(.headline)
                Spacer()
            }

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                GridRow {
                    label("Depth")
                    Text(depthText)
                }
                GridRow {
                    label("Positions")
                    Text(nodesText)
                }
                GridRow {
                    label("Elapsed")
                    Text(elapsedText)
                }
            }
            .font(.callout.monospacedDigit())

            Text("The first solution found is provably shortest. Typical cubes take a few minutes; unlucky ones longer.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Cancel", role: .cancel) {
                model.cancelOptimalSolve()
            }
            .buttonStyle(.glass)
        }
        .padding(16)
        .glassEffect(in: .rect(cornerRadius: 24))
        .frame(maxWidth: 440)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .font(.callout)
    }

    private var depthText: String {
        if let upper = session.upperBound {
            return "\(session.currentBound) of at most \(upper)"
        }
        return "\(session.currentBound)"
    }

    private var nodesText: String {
        let nodes = session.nodesSearched
        let seconds = max(session.elapsed.seconds, 0.001)
        let rate = Double(nodes) / seconds
        return "\(nodes.formatted()) · \(Int(rate / 1_000_000)) M/s"
    }

    private var elapsedText: String {
        let total = Int(session.elapsed.seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
