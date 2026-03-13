import SwiftUI
import AppKit

struct CellView: View {
    let cell: Cell
    let session: TerminalSession?
    let onUpdateLabel: (String) -> Void
    let onUpdateNotes: (String) -> Void
    let onUpdateWorkingDirectory: (String) -> Void
    let onRestartSession: () -> Void

    @State private var isEditingLabel = false
    @State private var labelDraft = ""
    @State private var showNotes = true
    @FocusState private var labelFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerView
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            // Body: terminal + optional notes panel
            HStack(spacing: 0) {
                terminalBody
                if showNotes {
                    Divider()
                    NotesView(notes: cell.notes, onUpdate: onUpdateNotes)
                        .frame(width: 160)
                }
            }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        )
    }

    // MARK: - Header

    @ViewBuilder
    private var headerView: some View {
        HStack {
            if isEditingLabel {
                TextField("Untitled", text: $labelDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .focused($labelFieldFocused)
                    .onSubmit { commitLabel() }
                    .onKeyPress(.escape) {
                        cancelLabel()
                        return .handled
                    }
                    .onChange(of: labelFieldFocused) { _, focused in
                        if !focused && isEditingLabel { commitLabel() }
                    }
                    .onAppear {
                        labelDraft = cell.label
                        labelFieldFocused = true
                    }
            } else {
                Text(cell.label.isEmpty ? "Untitled" : cell.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(cell.label.isEmpty ? .tertiary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        labelDraft = cell.label
                        isEditingLabel = true
                    }
            }

            Spacer()

            // Folder picker button
            Button(action: pickWorkingDirectory) {
                Image(systemName: "folder")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .help("Set working directory")

            // Notes toggle button
            Button(action: { showNotes.toggle() }) {
                Image(systemName: showNotes ? "note.text" : "note.text.badge.plus")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .help(showNotes ? "Hide notes" : "Show notes")
        }
    }

    // MARK: - Terminal Body

    @ViewBuilder
    private var terminalBody: some View {
        if let session {
            ZStack {
                TerminalContainerView(session: session)
                    .id(session.sessionID)

                if !session.isRunning {
                    // Session ended overlay
                    VStack(spacing: 8) {
                        Text("Session ended")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        Button("Restart") {
                            onRestartSession()
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
                }
            }
        } else {
            // Fallback if no session yet
            VStack {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Text("Starting terminal...")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Actions

    private func commitLabel() {
        isEditingLabel = false
        if labelDraft != cell.label {
            onUpdateLabel(labelDraft)
        }
    }

    private func cancelLabel() {
        isEditingLabel = false
    }

    private func pickWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: cell.workingDirectory)
        panel.prompt = "Select"
        panel.message = "Choose a working directory for this terminal"

        if panel.runModal() == .OK, let url = panel.url {
            onUpdateWorkingDirectory(url.path)
        }
    }
}
