import SwiftUI
import MarkdownUI
import AppKit

struct NotesView: View {
    let cellID: UUID
    let notes: String
    let onUpdate: (String) -> Void

    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("NOTES")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.notesSecondary)
                .textCase(.uppercase)
                .padding(.bottom, 4)

            if isEditing {
                TextEditor(text: $draft)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.notesText)
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
                            .foregroundColor(Theme.composePlaceholder)
                    } else {
                        Markdown(notes)
                            .markdownTextStyle {
                                FontSize(12)
                                ForegroundColor(Theme.notesText)
                            }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
                .onTapGesture { startEdit() }
            }
        }
        .padding(8)
        .background(Theme.notesBackground)
        .onChange(of: editorFocused) { _, focused in
            if !focused && isEditing {
                commitEdit()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusNotesPanel)) { notification in
            guard let targetID = notification.object as? UUID, targetID == cellID else { return }
            if !isEditing {
                startEdit()
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
