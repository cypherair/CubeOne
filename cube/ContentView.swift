import SwiftUI

/// Root navigation: Cube (play), Stats, Settings. On iOS 26 the TabView
/// renders as the floating Liquid Glass bottom bar.
struct ContentView: View {
    @State private var model: AppModel

    init() {
        _model = State(initialValue: AppModel(settings: SettingsStore()))
    }

    var body: some View {
        TabView {
            Tab("Cube", systemImage: "cube") {
                PlayView(model: model)
            }
            Tab("Stats", systemImage: "chart.bar") {
                StatsView(stats: model.stats)
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView(model: model)
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}
