import SwiftUI

/// Timed-solve mode: shows scramble progress, the live clock, and the
/// result. The clock starts on the user's first turn and stops itself
/// when the cube reaches solved.
struct TimerOverlay: View {
    let model: AppModel
    let session: AppModel.TimerSession

    var body: some View {
        VStack(spacing: 12) {
            content
            Button(doneButtonTitle, role: isFinished ? nil : .cancel) {
                model.exitTimerMode()
            }
            .buttonStyle(.glass)
        }
        .padding(20)
        .glassEffect(in: .rect(cornerRadius: 24))
        .frame(maxWidth: 420)
    }

    private var isFinished: Bool {
        if case .finished = session.phase { return true }
        return false
    }

    private var doneButtonTitle: String {
        isFinished ? "Done" : "Cancel"
    }

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .scrambling:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Scrambling…")
                    .font(.headline)
            }
        case .ready:
            VStack(spacing: 4) {
                Text("Ready")
                    .font(.headline)
                Text("The clock starts on your first turn")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .running(let start):
            TimelineView(.animation(minimumInterval: 0.03)) { context in
                Text(formatSolveDuration(
                    max(0, context.date.timeIntervalSince(start))))
                    .font(.system(size: 44, weight: .semibold, design: .rounded)
                        .monospacedDigit())
            }
        case .finished(let duration, let isBest):
            VStack(spacing: 4) {
                Text(formatSolveDuration(duration))
                    .font(.system(size: 44, weight: .bold, design: .rounded)
                        .monospacedDigit())
                    .foregroundStyle(isBest ? .yellow : .primary)
                if isBest {
                    Label("New best!", systemImage: "trophy.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.yellow)
                } else {
                    Text("^[\(session.moveCount) move](inflect: true)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
