import CubeKit
import SwiftUI

/// An unfolded cube net (U on top; L F R B across; D below) previewing
/// the current color scheme — all six faces visible at once.
struct CubeNetPreview: View {
    let settings: SettingsStore

    private let tile: CGFloat = 13
    private let gap: CGFloat = 2
    private let faceGap: CGFloat = 5

    var body: some View {
        VStack(spacing: faceGap) {
            HStack(spacing: faceGap) {
                faceGrid(nil)
                faceGrid(.up)
                faceGrid(nil)
                faceGrid(nil)
            }
            HStack(spacing: faceGap) {
                faceGrid(.left)
                faceGrid(.front)
                faceGrid(.right)
                faceGrid(.back)
            }
            HStack(spacing: faceGap) {
                faceGrid(nil)
                faceGrid(.down)
                faceGrid(nil)
                faceGrid(nil)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Cube color preview")
    }

    @ViewBuilder
    private func faceGrid(_ face: Face?) -> some View {
        let size = tile * 3 + gap * 2
        if let face {
            VStack(spacing: gap) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: gap) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(settings.color(for: face))
                                .frame(width: tile, height: tile)
                        }
                    }
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color(white: 0.1)))
        } else {
            Color.clear.frame(width: size + 4, height: size + 4)
        }
    }
}
