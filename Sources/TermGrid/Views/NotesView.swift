import SwiftUI
import MarkdownUI
import AppKit

struct NotesView: View {
    let cellID: UUID
    let notes: String
    let onUpdate: (String) -> Void
    var onSendToTerminal: ((String) -> Void)? = nil
    let sidebarNotesModel: SidebarNotesModel
    let baseDirectory: String
    var onEditNote: ((String) -> Void)? = nil

    @State private var isEditing = false
    @State private var draft = ""
    @State private var isCreating = false
    @State private var newNoteName = ""
    @State private var copiedPath: String? = nil
    @State private var hoveredNoteID: String? = nil
    @FocusState private var editorFocused: Bool
    @FocusState private var newNoteFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - Notes Header
            notesHeader

            // MARK: - Create Form (inline, replaces list temporarily)
            if isCreating {
                createNoteForm
            }

            // MARK: - Notes Pill List
            notesList

            // MARK: - Divider
            Rectangle()
                .fill(Theme.notesSecondary.opacity(0.2))
                .frame(height: 1)
                .padding(.vertical, 6)

            // MARK: - Scratch Pad
            scratchPadSection
        }
        .padding(8)
        .background(Theme.notesBackground)
        .onAppear {
            sidebarNotesModel.loadNotes(baseDirectory: baseDirectory)
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusNotesPanel)) { notification in
            guard let targetID = notification.object as? UUID, targetID == cellID else { return }
            if !isEditing {
                startEdit()
            }
        }
    }

    // MARK: - Notes Header

    private var notesHeader: some View {
        HStack {
            Text("NOTES")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.notesSecondary)
                .textCase(.uppercase)

            Spacer()

            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    isCreating.toggle()
                    if isCreating {
                        newNoteName = ""
                    }
                }
            } label: {
                Image(systemName: isCreating ? "xmark" : "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.accent)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Create Note Form

    private var createNoteForm: some View {
        VStack(spacing: 4) {
            TextField("filename", text: $newNoteName)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(Theme.notesText)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.cellBackground)
                )
                .focused($newNoteFieldFocused)
                .onAppear { newNoteFieldFocused = true }
                .onSubmit { commitCreate() }
                .onKeyPress(.escape) {
                    isCreating = false
                    return .handled
                }

            Button("Create") { commitCreate() }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.accent)
                .disabled(newNoteName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.bottom, 6)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Notes Pill List

    private var notesList: some View {
        ScrollView {
            if sidebarNotesModel.notes.isEmpty && !isCreating {
                VStack(spacing: 4) {
                    Text("No notes yet")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.composePlaceholder)
                    Text("Press + to create one")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.composePlaceholder.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            } else {
                LazyVStack(spacing: 3) {
                    ForEach(sidebarNotesModel.notes) { note in
                        notePill(note)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
        .layoutPriority(1)
    }

    private func notePill(_ note: SidebarNotesModel.NoteItem) -> some View {
        let isHovered = hoveredNoteID == note.id
        return HStack(spacing: 2) {
            Image(systemName: "doc.text")
                .font(.system(size: 9))
                .foregroundColor(isHovered ? Theme.accent : Theme.notesSecondary)

            Text(note.name)
                .font(.system(size: 11))
                .foregroundColor(Theme.notesText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Copy path button
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(note.path, forType: .string)
                withAnimation(.easeOut(duration: 0.15)) {
                    copiedPath = note.id
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation { copiedPath = nil }
                }
            } label: {
                Image(systemName: copiedPath == note.id ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 9))
                    .foregroundColor(copiedPath == note.id ? Theme.staged : Theme.notesSecondary)
                    .frame(width: 18, height: 18)
                    .scaleEffect(copiedPath == note.id ? 1.2 : 1.0)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .frame(height: 28)
        .contentShape(Rectangle())
        .onTapGesture { onEditNote?(note.path) }
        .onHover { hovering in hoveredNoteID = hovering ? note.id : nil }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Theme.cellBackground.opacity(0.8) : Theme.cellBackground.opacity(0.5))
        )
    }

    // MARK: - Scratch Pad

    private var scratchPadSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SCRATCH PAD")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Theme.notesSecondary.opacity(0.6))
                .textCase(.uppercase)

            if isEditing {
                TextEditor(text: $draft)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.notesText)
                    .scrollContentBackground(.hidden)
                    .focused($editorFocused)
                    .onAppear {
                        NSApp.activate(ignoringOtherApps: true)
                        DispatchQueue.main.async { editorFocused = true }
                    }
                    .onKeyPress(.escape) {
                        commitEdit()
                        return .handled
                    }
            } else {
                ScrollView {
                    Group {
                        if notes.isEmpty {
                            Text("Click to jot ideas...")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.composePlaceholder)
                        } else {
                            Markdown(notes)
                                .markdownTextStyle {
                                    FontSize(11)
                                    ForegroundColor(Theme.notesText)
                                }
                                .markdownBlockStyle(\.codeBlock) { config in
                                    RunnableCodeBlock(
                                        configuration: config,
                                        onSendToTerminal: onSendToTerminal
                                    )
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .contentShape(Rectangle())
                .onTapGesture { startEdit() }
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Theme.cellBackground.opacity(0.3))
        )
        .frame(minHeight: 80)
        .onChange(of: editorFocused) { _, focused in
            if !focused && isEditing { commitEdit() }
        }
    }

    // MARK: - Actions

    private func startEdit() {
        draft = notes
        isEditing = true
    }

    private func commitEdit() {
        isEditing = false
        if draft != notes { onUpdate(draft) }
    }

    private func commitCreate() {
        let name = newNoteName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if let path = sidebarNotesModel.createNote(named: name, baseDirectory: baseDirectory) {
            isCreating = false
            newNoteName = ""
            onEditNote?(path)
        }
    }
}
