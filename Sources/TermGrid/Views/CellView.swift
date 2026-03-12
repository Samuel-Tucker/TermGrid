import SwiftUI
import AppKit

struct CellView: View {
    let cell: Cell
    let onUpdateLabel: (String) -> Void
    let onUpdateNotes: (String) -> Void

    @State private var isEditingLabel = false
    @State private var labelDraft = ""
    @State private var isHoveringTerminal = false
    @FocusState private var labelFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerView
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            // Body: terminal area + notes panel
            HStack(spacing: 0) {
                terminalArea
                Divider()
                NotesView(notes: cell.notes, onUpdate: onUpdateNotes)
                    .frame(width: 160)
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
    }

    private func commitLabel() {
        isEditingLabel = false
        if labelDraft != cell.label {
            onUpdateLabel(labelDraft)
        }
    }

    private func cancelLabel() {
        isEditingLabel = false
    }

    // MARK: - Terminal Area

    private var terminalArea: some View {
        VStack {
            Spacer()
            Image(systemName: "terminal")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("Open Terminal")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isHoveringTerminal ? Color.accentColor.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHoveringTerminal = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onTapGesture { launchTerminal() }
    }

    private func launchTerminal() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal"]
        do {
            try process.run()
        } catch {
            print("[TermGrid] Failed to launch Terminal: \(error)")
        }
    }
}
