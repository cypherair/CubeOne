import CubeKit
import SwiftUI

struct ContentView: View {
    @State private var model = AppModel()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.13), Color(white: 0.05)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            CubeView(model: model)

            VStack {
                statusHeader
                Spacer()
                historyStrip
                ControlBar(model: model)
                    .padding(.bottom, 18)
            }
            .padding(.horizontal)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var statusHeader: some View {
        if case .preparing = model.solverStatus {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Preparing solver…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect()
            .padding(.top, 8)
        } else if case .failed = model.solverStatus {
            Label("Solver unavailable", systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect()
                .padding(.top, 8)
        } else if model.userMoveCount > 0 {
            Text("^[\(model.userMoveCount) move](inflect: true)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect()
                .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var historyStrip: some View {
        if !model.history.isEmpty {
            Text(historyText)
                .font(.system(.footnote, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.head)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .glassEffect()
                .padding(.bottom, 10)
                .frame(maxWidth: 420)
        }
    }

    private var historyText: String {
        let applied = Array(model.history.prefix(model.historyCursor))
        return applied.suffix(16).notation
    }
}

#Preview {
    ContentView()
}
