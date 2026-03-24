import SwiftUI

struct TerminalLabelBar: View {
    let label: String
    let placeholder: String
    let agentType: AgentType?
    let onCommit: (String) -> Void
    let onClose: (() -> Void)?

    @State private var isEditing = false
    @State private var draft = ""
    @State private var isBarHovered = false
    @State private var isCloseHovered = false
    @FocusState private var fieldFocused: Bool

    /// Display name used for the confirmation alert.
    var displayName: String {
        if let agent = agentType {
            return agent.displayName
        }
        return label.isEmpty ? "this terminal" : "'\(label)'"
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(Theme.composePlaceholder)

            if let agent = agentType {
                HStack(spacing: 3) {
                    Image(systemName: agent.iconName)
                        .font(.system(size: 8))
                    Text(agent.displayName)
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.9))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(agent.badgeColor.opacity(0.8)))
            }

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

            // Per-terminal close button — hover-only, plain xmark (no circle),
            // muted default → red on hover, distinguished from header X
            if onClose != nil {
                Button {
                    onClose?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(isCloseHovered ? Theme.error : Theme.headerIcon)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(isBarHovered ? 1 : 0)
                .scaleEffect(isCloseHovered ? 1.15 : (isBarHovered ? 1.0 : 0.9))
                .animation(.easeOut(duration: 0.15), value: isCloseHovered)
                .animation(.easeOut(duration: 0.15), value: isBarHovered)
                .onHover { hovering in
                    isCloseHovered = hovering
                }
                .tooltip("Close this terminal")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Theme.labelBarBackground)
        .onHover { hovering in
            isBarHovered = hovering
        }
    }

    private func commit() {
        isEditing = false
        if draft != label {
            onCommit(draft)
        }
    }
}
