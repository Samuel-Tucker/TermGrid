import SwiftUI

struct TerminalLabelBar: View {
    let label: String
    let placeholder: String
    let onCommit: (String) -> Void

    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(Theme.composePlaceholder)

            if isEditing {
                TextField(placeholder, text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.labelBarTextActive)
                    .focused($fieldFocused)
                    .onSubmit { commit() }
                    .onKeyPress(.escape) {
                        isEditing = false
                        return .handled
                    }
                    .onChange(of: fieldFocused) { _, focused in
                        if !focused && isEditing { commit() }
                    }
                    .onAppear {
                        draft = label
                        fieldFocused = true
                    }
            } else {
                Text(label.isEmpty ? placeholder : label)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(label.isEmpty ? Theme.composePlaceholder : Theme.labelBarText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        draft = label
                        isEditing = true
                    }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Theme.labelBarBackground)
    }

    private func commit() {
        isEditing = false
        if draft != label {
            onCommit(draft)
        }
    }
}
