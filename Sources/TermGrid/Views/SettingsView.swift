import SwiftUI

struct SettingsView: View {
    @AppStorage("hoverDimmingEnabled") private var hoverDimmingEnabled = false

    var body: some View {
        Form {
            Section("Appearance") {
                Toggle("Dim inactive panels on hover", isOn: $hoverDimmingEnabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 350, height: 120)
    }
}
