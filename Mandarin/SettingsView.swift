import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultOutputFolder") private var defaultOutputFolder = "Beside original"
    @AppStorage("defaultQuality") private var defaultQuality = 88.0

    var body: some View {
        Form {
            Section("Output") {
                Picker("Save converted files", selection: $defaultOutputFolder) {
                    Text("Beside original").tag("Beside original")
                    Text("Ask each time").tag("Ask each time")
                }

                Slider(value: $defaultQuality, in: 50...100, step: 1) {
                    Text("Image quality")
                } minimumValueLabel: {
                    Text("50")
                } maximumValueLabel: {
                    Text("100")
                }

                Text("Quality: \(Int(defaultQuality))%")
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("Everything stays on your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 340)
    }
}

#Preview {
    SettingsView()
}
