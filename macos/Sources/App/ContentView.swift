import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "viewfinder")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 4) {
                Text("Bobrshot")
                    .font(.title.bold())
                Text("Native capture tools are being assembled.")
                    .foregroundStyle(.secondary)
            }

            Divider()

            LabeledContent("Core", value: BobrshotCore.version.description)
                .font(.callout.monospacedDigit())
        }
        .padding(24)
        .frame(width: 420)
    }
}

#Preview {
    ContentView()
}
