import SwiftUI

/// All cube-manipulation preferences in one place.
struct ControlsSettingsView: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Picker("Lock mode", selection: $settings.lockMode) {
                    ForEach(SettingsStore.LockMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Locks")
            } footer: {
                Text("Layers only: turn layers, the whole cube stays put. View only: rotate the whole cube, layers stay put. Also cycled by the padlock on the play screen.")
            }

            Section("Gestures") {
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

                #if os(iOS)
                Toggle("Rotate with two fingers", isOn: $settings.twoFingerOrbit)
                Text("One finger only turns layers; rotating the whole cube takes two fingers. Pinch zoom still works.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                #endif
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Controls")
    }
}
