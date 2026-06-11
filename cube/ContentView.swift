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
                if let session = model.solveSession {
                    SolutionPanel(model: model, session: session)
                        .padding(.bottom, 18)
                } else if let editorSession = model.editor {
                    EditorPanel(model: model, session: editorSession)
                        .padding(.bottom, 18)
                } else if let timerSession = model.timerSession {
                    TimerOverlay(model: model, session: timerSession)
                        .padding(.bottom, 18)
                } else {
                    historyStrip
                    ControlBar(model: model)
                        .padding(.bottom, 18)
                }
            }
            .padding(.horizontal)
            .animation(.snappy, value: model.solveSession != nil)
            .animation(.snappy, value: model.editor != nil)
            .animation(.snappy, value: model.timerSession != nil)

            VStack {
                HStack {
                    Spacer()
                    Button {
                        showStats = true
                    } label: {
                        Image(systemName: "chart.bar")
                            .accessibilityLabel("Stats")
                    }
                    .buttonStyle(.glass)
                    .padding(.top, 8)
                    .padding(.trailing, 8)
                }
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.impact(weight: .light), trigger: model.committedMoveCount)
        .sheet(isPresented: $showStats) {
            StatsSheet(stats: model.stats)
        }
    }

    @State private var showStats = false

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
