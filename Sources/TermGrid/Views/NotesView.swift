import SwiftUI
import MarkdownUI
import AppKit

struct NotesView: View {
    let notes: String
    let onUpdate: (String) -> Void

    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("NOTES")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.bottom, 4)

            if isEditing {
                TextEditor(text: $draft)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .focused($editorFocused)
                    .onAppear {
                        NSApp.activate(ignoringOtherApps: true)
                        DispatchQueue.main.async {
                            editorFocused = true
                        }
                    }
                    .onKeyPress(.escape) {
                        commitEdit()
                        return .handled
                    }
            } else {
                Group {
                    if notes.isEmpty {
                        Text("Click to add notes...")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    } else {
                        Markdown(notes)
                            .markdownTextStyle {
                                FontSize(12)
                            }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
                .onTapGesture { startEdit() }
            }
        }
        .padding(8)
        .onChange(of: editorFocused) { _, focused in
            if !focused && isEditing {
                commitEdit()
            }
        }
    }

    private func startEdit() {
        draft = notes
        isEditing = true
    }

    private func commitEdit() {
        isEditing = false
        if draft != notes {
            onUpdate(draft)
        }
    }
}
