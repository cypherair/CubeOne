import CubeKit
import SwiftUI

/// Shows how the cube was scrambled: notation chips, replay, copy.
struct ScramblePanel: View {
    let model: AppModel
    let scramble: [Move]
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Scramble · \(scramble.count) moves")
                    .font(.headline)
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .accessibilityLabel("Close scramble")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(scramble.enumerated()), id: \.offset) { _, move in
                        Text(move.notation)
                            .font(.system(.callout, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.white.opacity(0.12))
                            )
                    }
                }
                .padding(.vertical, 2)
            }

            HStack(spacing: 14) {
                Button {
                    model.replayScramble()
                } label: {
                    Label("Replay", systemImage: "play.circle")
                }
                .disabled(!model.canReplayScramble)

                Button {
                    copyToPasteboard(scramble.notation)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
            .buttonStyle(.glass)
        }
        .padding(16)
        .glassEffect(in: .rect(cornerRadius: 24))
        .frame(maxWidth: 480)
    }

    private func copyToPasteboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}
