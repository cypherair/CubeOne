import CubeKit
import SwiftUI

struct ContentView: View {
    @State private var model = AppModel()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.12), Color(white: 0.05)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            CubeView(model: model)

            VStack {
                Spacer()
                Text(model.moveHistory.suffix(12).notation)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)
            }
        }
    }
}

#Preview {
    ContentView()
}
