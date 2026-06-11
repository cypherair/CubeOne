import SwiftUI
import CubeKit

struct ContentView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Cube One")
                .font(.largeTitle.bold())
            Text("CubeKit \(CubeKitInfo.version)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
