import SwiftUI
import MarkdownUI
import AppKit

struct ProjectNotesView: View {
    let cellID: UUID
    let effectiveDirectory: String
    let onChooseDirectory: () -> Void
    var onSendToTerminal: ((String) -> Void)? = nil

    @State private var model: ProjectNotesModel
    @State private var selectedNote: String? = nil
    @State private var noteContent: String = ""
    @State private var isEditing: Bool = false
    @State private var isCreatingItem: Bool = false
    @State private var newItemIsFolder: Bool = false
    @State private var newItemName: String = ""

    var initialNotePath: String? = nil

    init(cellID: UUID, effectiveDirectory: String,
         onChooseDirectory: @escaping () -> Void,
         onSendToTerminal: ((String) -> Void)? = nil,
         initialNotePath: String? = nil) {
        self.cellID = cellID
        self.effectiveDirectory = effectiveDirectory
        self.onChooseDirectory = onChooseDirectory
        self.onSendToTerminal = onSendToTerminal
        self.initialNotePath = initialNotePath
        self._model = State(initialValue: ProjectNotesModel(baseDirectory: effectiveDirectory))
        if let path = initialNotePath {
            self._selectedNote = State(initialValue: path)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if effectiveDirectory.isEmpty {
                emptyDirectoryState
            } else if !model.notesDirectoryExists {
                noNotesDirectoryState
            } else if let notePath = selectedNote {
                noteEditorView(path: notePath)
            } else {
                fileBrowserView
            }
        }
        .background(Theme.notesBackground)
        .onAppear {
            if model.notesDirectoryExists {
                model.loadContents()
            }
        }
        .onChange(of: effectiveDirectory) { _, newDir in
            model = ProjectNotesModel(baseDirectory: newDir)
            selectedNote = nil
            noteContent = ""
            isEditing = false
            if model.notesDirectoryExists {
                model.loadContents()
            }
        }
    }

    // MARK: - Empty / Error States

    private var emptyDirectoryState: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 32))
                .foregroundColor(Theme.composePlaceholder)
            Text("Set a directory first")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.notesText)
            Button("Choose directory...") {
                onChooseDirectory()
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noNotesDirectoryState: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 32))
                .foregroundColor(Theme.composePlaceholder)
            Text("No .termgrid/notes/ folder")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.notesText)
            Text(shortenedPath(effectiveDirectory))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Theme.composePlaceholder)
                .lineLimit(1)
            Button("Create .termgrid/notes/ here") {
                if model.ensureNotesDirectory() {
                    model.loadContents()
                }
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
            Button("Choose directory...") {
                onChooseDirectory()
            }
            .buttonStyle(.borderless)
            .foregroundColor(Theme.accent)
            .font(.system(size: 12))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - File Browser

    private var fileBrowserView: some View {
        VStack(spacing: 0) {
            // Breadcrumb bar
            HStack(spacing: 2) {
                ForEach(Array(model.pathComponents.enumerated()), id: \.offset) { index, component in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 7))
                            .foregroundColor(Theme.composePlaceholder)
                    }
                    Button(component) {
                        if index == 0 {
                            model.navigateTo(model.notesRoot)
                        } else {
                            // Build path from root + components
                            let parts = Array(model.pathComponents.dropFirst().prefix(index))
                            let target = (model.notesRoot as NSString).appendingPathComponent(parts.joined(separator: "/"))
                            model.navigateTo(target)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: index == model.pathComponents.count - 1 ? .semibold : .regular))
                    .foregroundColor(index == model.pathComponents.count - 1 ? Theme.notesText : Theme.composePlaceholder)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Theme.headerBackground)

            // Toolbar
            HStack(spacing: 6) {
                // Search
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.composePlaceholder)
                    TextField("Search...", text: $model.searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.notesText)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 4).fill(Theme.cellBackground))

                Spacer()

                Button {
                    newItemIsFolder = false
                    newItemName = ""
                    isCreatingItem = true
                } label: {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.headerIcon)
                }
                .buttonStyle(.plain)
                .tooltip("New note")

                Button {
                    newItemIsFolder = true
                    newItemName = ""
                    isCreatingItem = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.headerIcon)
                }
                .buttonStyle(.plain)
                .tooltip("New folder")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Theme.divider.frame(height: 1)

            // New item inline form
            if isCreatingItem {
                HStack(spacing: 6) {
                    Image(systemName: newItemIsFolder ? "folder" : "doc.text")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.accent)
                    TextField(newItemIsFolder ? "Folder name" : "Note name", text: $newItemName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.notesText)
                        .onSubmit { commitNewItem() }
                        .onKeyPress(.escape) {
                            isCreatingItem = false
                            return .handled
                        }
                    Button("Create") { commitNewItem() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.accent)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.headerBackground)
                Theme.divider.frame(height: 1)
            }

            // File list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Back row
                    if model.canNavigateBack {
                        Button {
                            model.navigateBack()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.left")
                                    .font(.system(size: 10))
                                    .foregroundColor(Theme.accent)
                                Text("..")
                                    .font(.system(size: 12))
                                    .foregroundColor(Theme.notesText)
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(model.filteredItems) { item in
                        Button {
                            if item.isDirectory {
                                model.navigateTo(item.path)
                            } else {
                                openNote(at: item.path)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: item.isDirectory ? "folder.fill" : "doc.text")
                                    .font(.system(size: 11))
                                    .foregroundColor(item.isDirectory ? Theme.accent : Theme.headerIcon)
                                Text(item.name)
                                    .font(.system(size: 12))
                                    .foregroundColor(Theme.notesText)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    if model.filteredItems.isEmpty && !isCreatingItem {
                        VStack(spacing: 8) {
                            Text("No notes yet")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.composePlaceholder)
                            Button("Create a note") {
                                newItemIsFolder = false
                                newItemName = ""
                                isCreatingItem = true
                            }
                            .buttonStyle(.borderless)
                            .foregroundColor(Theme.accent)
                            .font(.system(size: 12))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                    }
                }
            }
        }
    }

    // MARK: - Note Editor

    private func noteEditorView(path: String) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Button {
                    if isEditing {
                        _ = model.writeNote(at: path, content: noteContent)
                    }
                    selectedNote = nil
                    isEditing = false
                    model.loadContents()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.accent)
                }
                .buttonStyle(.plain)

                Text((path as NSString).lastPathComponent)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.notesText)
                    .lineLimit(1)

                Spacer()

                if isEditing {
                    Button("Save") {
                        _ = model.writeNote(at: path, content: noteContent)
                        isEditing = false
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.accent)

                    Button("Cancel") {
                        noteContent = model.readNote(at: path) ?? ""
                        isEditing = false
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.composePlaceholder)
                } else {
                    Button {
                        isEditing = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.headerIcon)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Theme.headerBackground)

            Theme.divider.frame(height: 1)

            // Content
            if isEditing {
                FileEditorTextView(text: $noteContent)
            } else {
                ScrollView {
                    if noteContent.isEmpty {
                        Text("Empty note. Click edit to start writing.")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.composePlaceholder)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(8)
                    } else if (path as NSString).pathExtension.lowercased() == "md" {
                        Markdown(noteContent)
                            .markdownTextStyle {
                                FontSize(12)
                                ForegroundColor(Theme.notesText)
                            }
                            .markdownBlockStyle(\.codeBlock) { config in
                                RunnableCodeBlock(
                                    configuration: config,
                                    onSendToTerminal: onSendToTerminal
                                )
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(8)
                    } else {
                        Text(noteContent)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(Theme.notesText)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(8)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func openNote(at path: String) {
        noteContent = model.readNote(at: path) ?? ""
        isEditing = false
        selectedNote = path
    }

    private func commitNewItem() {
        guard !newItemName.isEmpty else { return }
        if newItemIsFolder {
            _ = model.createFolder(named: newItemName)
        } else {
            _ = model.createNote(named: newItemName)
        }
        isCreatingItem = false
        newItemName = ""
    }

    private func shortenedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
