import SwiftUI

struct GridPickerView: View {
    @Binding var selection: GridPreset

    var body: some View {
        Picker("Grid", selection: $selection) {
            ForEach(GridPreset.allCases, id: \.self) { preset in
                Text(preset.rawValue).tag(preset)
            }
        }
        .pickerStyle(.menu)
    }
}
