import SwiftUI
import AppKit

struct CellView: View {
    let cell: Cell
    let session: TerminalSession?
    let splitSession: TerminalSession?
    let splitDirection: SplitDirection?
    let onUpdateLabel: (String) -> Void
    let onUpdateNotes: (String) -> Void
    let onUpdateWorkingDirectory: (String) -> Void
    let onRestartSession: () -> Void
    let onToggleSplit: (SplitDirection) -> Void
    let onRestartSplitSession: () -> Void
    let onUpdateTerminalLabel: (String) -> Void
    let onUpdateSplitTerminalLabel: (String) -> Void

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
                .background(Theme.headerBackground)

            Theme.divider.frame(height: 1)

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
        .background(Theme.cellBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.cellBorder, lineWidth: 1)
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
                    .foregroundColor(Theme.headerText)
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
                    .foregroundColor(cell.label.isEmpty ? Theme.headerIcon : Theme.headerText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        labelDraft = cell.label
                        isEditingLabel = true
                    }
            }

            Spacer()

            // Horizontal split button (top/bottom)
            Button {
                onToggleSplit(.horizontal)
            } label: {
                Image(systemName: splitDirection == .horizontal ? "square.split.1x2.fill" : "square.split.1x2")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.headerIcon)
            }
            .buttonStyle(.borderless)
            .help(splitDirection == .horizontal ? "Close horizontal split" : "Split horizontal")

            // Vertical split button (left/right)
            Button {
                onToggleSplit(.vertical)
            } label: {
                Image(systemName: splitDirection == .vertical ? "square.split.2x1.fill" : "square.split.2x1")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.headerIcon)
            }
            .buttonStyle(.borderless)
            .help(splitDirection == .vertical ? "Close vertical split" : "Split vertical")

            // Folder picker button
            Button(action: pickWorkingDirectory) {
                Image(systemName: "folder")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.headerIcon)
            }
            .buttonStyle(.borderless)
            .help("Set working directory")

            // Notes toggle button
            Button(action: { showNotes.toggle() }) {
                Image(systemName: showNotes ? "note.text" : "note.text.badge.plus")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.headerIcon)
            }
            .buttonStyle(.borderless)
            .help(showNotes ? "Hide notes" : "Show notes")
        }
    }

    // MARK: - Terminal Body

    @ViewBuilder
    private var terminalBody: some View {
        if splitSession != nil, let dir = splitDirection {
            splitContainer(direction: dir) {
                labeledTerminalPane(
                    session: session,
                    label: cell.terminalLabel,
                    placeholder: "Label terminal...",
                    onRestart: onRestartSession,
                    onUpdateLabel: onUpdateTerminalLabel
                )
                Divider()
                labeledTerminalPane(
                    session: splitSession,
                    label: cell.splitTerminalLabel,
                    placeholder: "Label terminal...",
                    onRestart: onRestartSplitSession,
                    onUpdateLabel: onUpdateSplitTerminalLabel
                )
            }
        } else {
            labeledTerminalPane(
                session: session,
                label: cell.terminalLabel,
                placeholder: "Label terminal...",
                onRestart: onRestartSession,
                onUpdateLabel: onUpdateTerminalLabel
            )
        }
    }

    @ViewBuilder
    private func splitContainer<Content: View>(direction: SplitDirection, @ViewBuilder content: () -> Content) -> some View {
        switch direction {
        case .horizontal:
            VStack(spacing: 0) { content() }
        case .vertical:
            HStack(spacing: 0) { content() }
        }
    }

    @ViewBuilder
    private func labeledTerminalPane(
        session: TerminalSession?,
        label: String,
        placeholder: String,
        onRestart: @escaping () -> Void,
        onUpdateLabel: @escaping (String) -> Void
    ) -> some View {
        VStack(spacing: 0) {
            TerminalLabelBar(label: label, placeholder: placeholder, onCommit: onUpdateLabel)
            terminalPane(session: session, onRestart: onRestart)
        }
    }

    @ViewBuilder
    private func terminalPane(session: TerminalSession?, onRestart: @escaping () -> Void) -> some View {
        if let session {
            VStack(spacing: 0) {
                ZStack {
                    TerminalContainerView(session: session)
                        .id(session.sessionID)

                    if !session.isRunning {
                        VStack(spacing: 8) {
                            Text("Session ended")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.overlayText)
                            Button("Restart", action: onRestart)
                                .buttonStyle(.bordered)
                                .tint(Theme.accent)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.cellBackground.opacity(0.85))
                    }
                }

                ComposeBox { text in
                    session.send(text)
                }
            }
        } else {
            VStack {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Text("Starting terminal...")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.composePlaceholder)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.cellBackground)
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
