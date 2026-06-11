import CubeKit
import SwiftUI

/// The Settings tab: cube colors, feedback, and interaction preferences.
struct SettingsView: View {
    @Bindable var settings: SettingsStore
    let model: AppModel

    init(model: AppModel) {
        self.model = model
        self.settings = model.settings
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Cube colors") {
                    ForEach(Face.allCases, id: \.rawValue) { face in
                        ColorPicker(face.displayName, selection: colorBinding(for: face))
                    }
                    HStack {
                        Text("Presets")
                        Spacer()
                        ForEach(SettingsStore.ColorPreset.allCases) { preset in
                            Button(preset.label) {
                                model.applyColorPreset(preset)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }

                Section("Feedback") {
                    Toggle("Turn sound", isOn: $settings.soundEnabled)
                    Toggle("Haptics", isOn: $settings.hapticsEnabled)
                }

                Section("Interaction") {
                    Picker("Turn speed", selection: $settings.turnSpeed) {
                        ForEach(SettingsStore.TurnSpeed.allCases) { speed in
                            Text(speed.label).tag(speed)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading) {
                        Text("Rotate sensitivity")
                        Slider(value: $settings.orbitSensitivity, in: 0.4...1.6)
                    }

                    Toggle("Rotation lock", isOn: $settings.rotationLock)

                    #if os(iOS)
                    Toggle("Rotate with two fingers", isOn: $settings.twoFingerOrbit)
                    Text("When on, one finger only turns faces; rotating the whole cube takes two fingers.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    #endif
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
        }
    }

    private func colorBinding(for face: Face) -> Binding<Color> {
        Binding(
            get: { settings.color(for: face) },
            set: { model.setFaceColor($0, for: face) }
        )
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
