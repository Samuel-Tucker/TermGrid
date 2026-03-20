import SwiftUI

struct WorkspaceTabBar: View {
    @Bindable var collection: WorkspaceCollection
    var onSwitchWorkspace: (Int) -> Void
    var onNewWorkspace: () -> Void
    var onCloseWorkspace: (Int) -> Void
    var onRenameWorkspace: (Int, String) -> Void
    var onDuplicateWorkspace: (Int) -> Void

    @State private var addHovered = false
    @State private var confirmCloseIndex: Int? = nil

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            // Centered tab group
            HStack(spacing: 6) {
                ForEach(Array(collection.workspaces.enumerated()), id: \.element.id) { index, workspace in
                    WorkspaceTab(
                        name: workspace.name,
                        isActive: index == collection.activeIndex,
                        isOnly: collection.workspaces.count == 1,
                        onSelect: { onSwitchWorkspace(index) },
                        onClose: { confirmCloseIndex = index },
                        onRename: { newName in onRenameWorkspace(index, newName) },
                        onDuplicate: { onDuplicateWorkspace(index) }
                    )
                }

                // "+" button — glassmorphic, with hover tooltip
                if collection.workspaces.count < WorkspaceCollection.maxWorkspaces {
                    Button(action: onNewWorkspace) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(addHovered ? Theme.headerText : Theme.headerIcon)
                            .frame(width: 30, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .shadow(color: .white.opacity(0.04), radius: 0, x: 0, y: 1)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(Color.white.opacity(addHovered ? 0.12 : 0.06), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.1)) { addHovered = hovering }
                    }
                    .tooltip("New Workspace (⌘T)")
                }
            }

            Spacer(minLength: 0)
        }
        .frame(height: 36)
        .background(Theme.headerBackground)
        .alert("Close Workspace",
               isPresented: Binding(
                   get: { confirmCloseIndex != nil },
                   set: { if !$0 { confirmCloseIndex = nil } }
               )
        ) {
            Button("Close", role: .destructive) {
                if let idx = confirmCloseIndex {
                    onCloseWorkspace(idx)
                }
                confirmCloseIndex = nil
            }
            Button("Cancel", role: .cancel) {
                confirmCloseIndex = nil
            }
        } message: {
            if let idx = confirmCloseIndex, idx < collection.workspaces.count {
                Text("Close \"\(collection.workspaces[idx].name)\"? All terminal sessions in this workspace will be terminated.")
            }
        }
    }
}

// MARK: - Single Tab

private struct WorkspaceTab: View {
    let name: String
    let isActive: Bool
    let isOnly: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onRename: (String) -> Void
    let onDuplicate: () -> Void

    @State private var isHovered = false
    @State private var isEditing = false
    @State private var editText = ""

    var body: some View {
        // Use a Button for the whole tab so click handling is clean
        Button(action: {
            if !isActive && !isEditing { onSelect() }
        }) {
            HStack(spacing: 5) {
                if isEditing {
                    TextField("", text: $editText, onCommit: {
                        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            onRename(trimmed)
                        }
                        isEditing = false
                    })
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.headerText)
                    .frame(minWidth: 50, maxWidth: 140)
                    .onExitCommand { isEditing = false }
                } else {
                    Text(name)
                        .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                        .foregroundColor(isActive ? Color(hex: "#D4C5B0") : Theme.headerIcon.opacity(0.55))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .background(
            ZStack {
                if isActive {
                    // Glassmorphic active pill
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .white.opacity(0.03), radius: 0, x: 0, y: 1)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                }
            }
        )
        // Close "x" overlaid on the right edge (hover-only, not for single workspace)
        .overlay(alignment: .topTrailing) {
            if isHovered && !isOnly && !isEditing {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(Theme.tabCloseButton)
                        .frame(width: 14, height: 14)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }
        }
        // Accent underline for active tab
        .overlay(alignment: .bottom) {
            if isActive {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.accent)
                    .frame(width: 20, height: 2)
                    .offset(y: 1)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
        .onTapGesture(count: 2) {
            editText = name
            isEditing = true
        }
        .contextMenu {
            Button("Rename") {
                editText = name
                isEditing = true
            }
            Button("Duplicate") { onDuplicate() }
            if !isOnly {
                Divider()
                Button("Close") { onClose() }
            }
        }
    }
}
