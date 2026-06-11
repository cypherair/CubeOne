import CubeKit
import SwiftUI

/// Sticker-painting mode: color palette, live validation, apply/cancel.
struct EditorPanel: View {
    let model: AppModel
    let session: AppModel.EditorSession

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Customize")
                    .font(.headline)
                Spacer()
                validationStatus
            }
            palette
            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    model.cancelEditing()
                }
                Button {
                    model.editorReplaceAll(with: .solved)
                } label: {
                    Label("Solved", systemImage: "arrow.counterclockwise")
                }
                Button {
                    model.applyEditing()
                } label: {
                    Label("Done", systemImage: "checkmark")
                        .fontWeight(.semibold)
                }
                .disabled(!session.isValid)
            }
            .buttonStyle(.glass)
            .controlSize(.regular)
        }
        .padding(16)
        .glassEffect(in: .rect(cornerRadius: 24))
        .frame(maxWidth: 480)
    }

    private var validationStatus: some View {
        Group {
            if let error = session.error {
                Label(error.friendlyText, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                Label("Solvable", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .font(.footnote)
        .lineLimit(2)
    }

    private var palette: some View {
        HStack(spacing: 12) {
            ForEach(Face.allCases, id: \.rawValue) { face in
                Button {
                    model.editorSelectColor(face)
                } label: {
                    Circle()
                        .fill(face.swiftUIColor)
                        .frame(width: 30, height: 30)
                        .overlay(
                            Circle().strokeBorder(
                                .white.opacity(session.selectedColor == face ? 0.9 : 0.15),
                                lineWidth: session.selectedColor == face ? 3 : 1
                            )
                        )
                        .shadow(radius: 1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Paint \(String(face.letter))")
            }
            Spacer()
            Text("Tap a sticker to paint it. Centers are fixed.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 130)
        }
    }
}

extension CubeValidationError {
    var friendlyText: String {
        switch self {
        case .wrongColorCounts: "Needs exactly 9 of each color"
        case .wrongCenters: "Centers are fixed"
        case .unrecognizablePiece: "A piece has an impossible color combination"
        case .duplicatePiece: "The same piece appears twice"
        case .cornerTwist: "A corner is twisted — unsolvable"
        case .edgeFlip: "An edge is flipped — unsolvable"
        case .permutationParity: "Two pieces are swapped — unsolvable"
        }
    }
}
