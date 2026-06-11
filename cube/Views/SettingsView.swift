import CubeKit
import SwiftUI

/// The Settings tab: a hub linking to Controls and Cube Colors pages,
/// with simple preferences inline.
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
                Section {
                    NavigationLink {
                        ControlsSettingsView(settings: model.settings)
                    } label: {
                        Label("Controls", systemImage: "hand.draw")
                    }
                    NavigationLink {
                        ColorSettingsView(model: model)
                    } label: {
                        Label("Cube Colors", systemImage: "paintpalette")
                    }
                }

                Section("Feedback") {
                    Toggle("Turn sound", isOn: $settings.soundEnabled)
                    Toggle("Haptics", isOn: $settings.hapticsEnabled)
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
