import SwiftUI
import MarkdownUI

/// MarkdownUI code block theme that adds Paste/Run hover buttons.
/// Use via `.markdownBlockStyle(\.codeBlock) { RunnableCodeBlock(configuration: $0, ...) }`
struct RunnableCodeBlock: View {
    let configuration: CodeBlockConfiguration
    let onSendToTerminal: ((String) -> Void)?

    @State private var isHovered = false
    @State private var flashColor: Color? = nil

    private static let shellLanguages: Set<String> = ["bash", "sh", "zsh", "shell", ""]

    private var isShell: Bool {
        let lang = (configuration.language ?? "").lowercased()
        return Self.shellLanguages.contains(lang)
    }

    private var code: String {
        configuration.content
    }

    var body: some View {
        configuration.label
            .padding(10)
            .background(Theme.appBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(flashColor ?? Color.clear, lineWidth: flashColor != nil ? 1.5 : 0)
            )
            .overlay(alignment: .topTrailing) {
                if isHovered && onSendToTerminal != nil {
                    HStack(spacing: 4) {
                        // Paste button (always)
                        codeActionButton(
                            icon: "doc.on.clipboard",
                            label: "Paste",
                            action: { pasteToTerminal(run: false) }
                        )

                        // Run button (shell only)
                        if isShell {
                            codeActionButton(
                                icon: "play.fill",
                                label: "Run",
                                action: { pasteToTerminal(run: true) }
                            )
                        }
                    }
                    .padding(6)
                    .transition(.opacity)
                }
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
            }
    }

    private func codeActionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Image(systemName: icon)
            .font(.system(size: 10))
            .foregroundColor(Theme.accent)
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.cellBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Theme.cellBorder, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
            .highPriorityGesture(TapGesture().onEnded { action() })
            .tooltip(label)
    }

    private func pasteToTerminal(run: Bool) {
        guard let send = onSendToTerminal else { return }
        // Bracketed paste: safe for multi-line, heredocs, etc.
        let bracketedPaste = "\u{1b}[200~" + code + "\u{1b}[201~"
        let payload = run ? bracketedPaste + "\r" : bracketedPaste
        send(payload)

        // Green flash feedback
        withAnimation(.easeIn(duration: 0.1)) {
            flashColor = Color(hex: "#75BE95")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeOut(duration: 0.3)) {
                flashColor = nil
            }
        }
    }
}
