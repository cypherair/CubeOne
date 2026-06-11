import CubeKit
import SwiftUI

/// Cube color customization: live net preview, presets, per-face pickers.
struct ColorSettingsView: View {
    let model: AppModel

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    CubeNetPreview(settings: model.settings)
                        .padding(.vertical, 6)
                    Spacer()
                }
            }

            Section("Presets") {
                HStack(spacing: 10) {
                    ForEach(SettingsStore.ColorPreset.allCases) { preset in
                        Button(preset.label) {
                            model.applyColorPreset(preset)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            Section("Faces") {
                ForEach(Face.allCases, id: \.rawValue) { face in
                    ColorPicker(face.displayName, selection: colorBinding(for: face))
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Cube Colors")
    }

    private func colorBinding(for face: Face) -> Binding<Color> {
        Binding(
            get: { model.settings.color(for: face) },
            set: { model.setFaceColor($0, for: face) }
        )
    }
}
