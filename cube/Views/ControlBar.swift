import SwiftUI

/// The floating Liquid Glass control bar. Falls back to icon-only
/// buttons when horizontal space is tight (iPhone).
struct ControlBar: View {
    let model: AppModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            bar(.titleAndIcon)
            bar(.iconOnly)
        }
    }

    private func bar(_ labelStyle: some LabelStyle) -> some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 14) {
                Button {
                    model.scramble()
                } label: {
                    Label("Scramble", systemImage: "shuffle")
                        .labelStyle(labelStyle)
                }
                .disabled(!model.canScramble)

                Button {
                    model.startSolve()
                } label: {
                    if model.isComputingSolution {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Solve", systemImage: "wand.and.stars")
                            .labelStyle(labelStyle)
                    }
                }
                .disabled(!model.canSolve)

                Button {
                    model.beginEditing()
                } label: {
                    Image(systemName: "paintpalette")
                        .accessibilityLabel("Customize cube")
                }
                .disabled(!model.canEdit)

                Button {
                    model.startTimerMode()
                } label: {
                    Image(systemName: "stopwatch")
                        .accessibilityLabel("Timed solve")
                }
                .disabled(!model.canStartTimer)

                Button {
                    model.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .accessibilityLabel("Undo")
                }
                .disabled(!model.canUndo)

                Button {
                    model.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .accessibilityLabel("Redo")
                }
                .disabled(!model.canRedo)

                Button {
                    model.reset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .accessibilityLabel("Reset to solved")
                }
                .disabled(!model.canReset)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
    }
}
