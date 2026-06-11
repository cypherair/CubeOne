import SwiftUI

/// The floating Liquid Glass control bar. Falls back to icon-only, then
/// to two rows, as horizontal space tightens (iPhone portrait).
struct ControlBar: View {
    let model: AppModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            singleRow(titles: true)
            singleRow(titles: false)
            twoRows
        }
    }

    private func singleRow(titles: Bool) -> some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 14) {
                scrambleButton(titles: titles)
                solveButton(titles: titles)
                customizeButton
                timerButton
                undoButton
                redoButton
                resetButton
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
    }

    private var twoRows: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    scrambleButton(titles: false)
                    solveButton(titles: false)
                    customizeButton
                    timerButton
                }
                HStack(spacing: 12) {
                    undoButton
                    redoButton
                    resetButton
                }
            }
            .buttonStyle(.glass)
            .controlSize(.regular)
        }
    }

    // MARK: Buttons

    private func scrambleButton(titles: Bool) -> some View {
        Button {
            model.scramble()
        } label: {
            Label("Scramble", systemImage: "shuffle")
                .labelStyle(titles ? AnyLabelStyle(.titleAndIcon) : AnyLabelStyle(.iconOnly))
        }
        .disabled(!model.canScramble)
    }

    private func solveButton(titles: Bool) -> some View {
        Button {
            model.startSolve()
        } label: {
            if model.isComputingSolution {
                ProgressView()
                    .controlSize(.small)
            } else {
                Label("Solve", systemImage: "wand.and.stars")
                    .labelStyle(titles ? AnyLabelStyle(.titleAndIcon) : AnyLabelStyle(.iconOnly))
            }
        }
        .disabled(!model.canSolve)
    }

    private var customizeButton: some View {
        Button {
            model.beginEditing()
        } label: {
            Image(systemName: "paintpalette")
                .accessibilityLabel("Customize cube")
        }
        .disabled(!model.canEdit)
    }

    private var timerButton: some View {
        Button {
            model.startTimerMode()
        } label: {
            Image(systemName: "stopwatch")
                .accessibilityLabel("Timed solve")
        }
        .disabled(!model.canStartTimer)
    }

    private var undoButton: some View {
        Button {
            model.undo()
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .accessibilityLabel("Undo")
        }
        .disabled(!model.canUndo)
    }

    private var redoButton: some View {
        Button {
            model.redo()
        } label: {
            Image(systemName: "arrow.uturn.forward")
                .accessibilityLabel("Redo")
        }
        .disabled(!model.canRedo)
    }

    private var resetButton: some View {
        Button {
            model.reset()
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .accessibilityLabel("Reset to solved")
        }
        .disabled(!model.canReset)
    }
}

/// Type-erased label style so a ternary can pick between styles.
private struct AnyLabelStyle: LabelStyle {
    private let makeBodyClosure: (Configuration) -> AnyView

    init(_ style: some LabelStyle) {
        makeBodyClosure = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        makeBodyClosure(configuration)
    }
}
