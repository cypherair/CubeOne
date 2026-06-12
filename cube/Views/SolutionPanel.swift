import CubeKit
import SwiftUI

/// The guided-solution panel: move chips with the current step
/// highlighted, plus playback controls.
struct SolutionPanel: View {
    let model: AppModel
    let session: AppModel.SolveSession

    var body: some View {
        VStack(spacing: 12) {
            header
            chips
            controls
        }
        .padding(16)
        .glassEffect(in: .rect(cornerRadius: 24))
        .frame(maxWidth: 480)
    }

    private var header: some View {
        HStack {
            if session.isFinished {
                Label("Solved!", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
            } else if let stage = session.currentStage, let stages = session.stages {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stage.marker.name)
                        .font(.headline)
                    Text("Stage \(stage.index + 1) of \(stages.count) · \(session.solution.count) moves")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if session.isOptimal {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Optimal · \(session.solution.count) moves")
                        .font(.headline)
                    Text("Proven shortest solution")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Solution · \(session.solution.count) moves")
                    .font(.headline)
            }
            Spacer()
            Button {
                model.endSolveSession()
            } label: {
                Image(systemName: "xmark")
                    .accessibilityLabel("Close solution")
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
    }

    private var chips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(session.solution.enumerated()), id: \.offset) { index, move in
                        Text(move.notation)
                            .font(.system(.callout, design: .monospaced).weight(
                                index == session.nextIndex ? .bold : .regular))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(chipColor(for: index))
                            )
                            .foregroundStyle(index < session.nextIndex ? .secondary : .primary)
                            .id(index)
                    }
                }
                .padding(.vertical, 2)
            }
            .onChange(of: session.nextIndex) { _, next in
                withAnimation {
                    proxy.scrollTo(min(next, session.solution.count - 1), anchor: .center)
                }
            }
        }
    }

    private func chipColor(for index: Int) -> Color {
        if index == session.nextIndex { return .accentColor.opacity(0.55) }
        if index < session.nextIndex { return .white.opacity(0.06) }
        return .white.opacity(0.14)
    }

    private var controls: some View {
        HStack(spacing: 18) {
            Button {
                model.solveStepBackward()
            } label: {
                Image(systemName: "backward.frame.fill")
                    .accessibilityLabel("Step back")
            }
            .disabled(session.nextIndex == 0)

            Button {
                model.solveTogglePlay()
            } label: {
                Image(systemName: session.isPlaying ? "pause.fill" : "play.fill")
                    .accessibilityLabel(session.isPlaying ? "Pause" : "Play")
            }
            .disabled(session.isFinished)

            Button {
                model.solveStepForward()
            } label: {
                Image(systemName: "forward.frame.fill")
                    .accessibilityLabel("Step forward")
            }
            .disabled(session.isFinished)
        }
        .buttonStyle(.glass)
        .controlSize(.regular)
    }
}
