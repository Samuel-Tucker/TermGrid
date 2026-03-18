import SwiftUI
import AppKit

struct FileExplorerView: View {
    let cellID: UUID
    let rootPath: String
    let viewMode: ExplorerViewMode
    let onViewModeChange: (ExplorerViewMode) -> Void

    @State private var model: FileExplorerModel
    @Binding var previewingFile: String?
    @State private var isCreatingNewItem = false
    @State private var newItemIsFolder = false
    @State private var newItemName = ""

    init(cellID: UUID, rootPath: String, viewMode: ExplorerViewMode,
         previewingFile: Binding<String?>,
         onViewModeChange: @escaping (ExplorerViewMode) -> Void) {
        self.cellID = cellID
        self.rootPath = rootPath
        self.viewMode = viewMode
        self._previewingFile = previewingFile
        self.onViewModeChange = onViewModeChange
        self._model = State(initialValue: FileExplorerModel(rootPath: rootPath))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let filePath = previewingFile {
                FilePreviewView(
                    filePath: filePath,
                    model: model,
                    onBack: { previewingFile = nil }
                )
            } else {
                breadcrumbBar
                Theme.divider.frame(height: 1)
                toolbar
                Theme.divider.frame(height: 1)

                if isCreatingNewItem {
                    newItemField
                    Theme.divider.frame(height: 1)
                }

                if model.filteredItems.isEmpty {
                    emptyState
                } else {
                    switch viewMode {
                    case .grid:
                        gridView
                    case .list:
                        listView
                    }
                }
            }
        }
        .background(Theme.cellBackground)
        .onAppear {
            model.loadContents()
        }
        .onChange(of: rootPath) { _, newPath in
            model.navigateTo(newPath)
        }
        .onReceive(NotificationCenter.default.publisher(for: .commandPaletteNewFile)) { notification in
            guard let targetID = notification.object as? UUID, targetID == cellID else { return }
            newItemIsFolder = false
            newItemName = ""
            isCreatingNewItem = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .commandPaletteNewFolder)) { notification in
            guard let targetID = notification.object as? UUID, targetID == cellID else { return }
            newItemIsFolder = true
            newItemName = ""
            isCreatingNewItem = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .commandPaletteToggleHidden)) { notification in
            guard let targetID = notification.object as? UUID, targetID == cellID else { return }
            model.showHiddenFiles.toggle()
            model.loadContents()
        }
    }

    // MARK: - Breadcrumb Bar

    @ViewBuilder
    private var breadcrumbBar: some View {
        HStack(spacing: 0) {
            // Back button
            Button {
                model.navigateBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(model.canNavigateBack ? Theme.accent : Theme.composePlaceholder)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(model.canNavigateBack ? Theme.accent.opacity(0.15) : Color.clear)
                    )
            }
            .buttonStyle(.borderless)
            .disabled(!model.canNavigateBack)
            .padding(.leading, 6)

            // Breadcrumbs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(model.pathComponents.enumerated()), id: \.offset) { index, component in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8))
                                .foregroundColor(Theme.composePlaceholder)
                        }
                        Button {
                            model.navigateToBreadcrumbIndex(index)
                        } label: {
                            Text(component)
                                .font(.system(size: 10, weight: index == model.pathComponents.count - 1 ? .semibold : .regular, design: .monospaced))
                                .foregroundColor(index == model.pathComponents.count - 1 ? Theme.accent : Theme.headerIcon)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Theme.cellBorder.opacity(0.5))
                                )
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
        }
        .background(Theme.headerBackground)
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbar: some View {
        HStack(spacing: 8) {
            // Search field
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.composePlaceholder)
                TextField("Filter...", text: $model.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.headerText)
                if !model.searchQuery.isEmpty {
                    Button {
                        model.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.composePlaceholder)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.appBackground)
            )

            Spacer()

            // Hidden files toggle
            Button {
                model.showHiddenFiles.toggle()
                model.loadContents()
            } label: {
                Image(systemName: model.showHiddenFiles ? "eye" : "eye.slash")
                    .font(.system(size: 11))
                    .foregroundColor(model.showHiddenFiles ? Theme.accent : Theme.headerIcon)
            }
            .buttonStyle(.borderless)
            .help(model.showHiddenFiles ? "Hide hidden files" : "Show hidden files")

            // View mode toggle
            Button {
                onViewModeChange(viewMode == .grid ? .list : .grid)
            } label: {
                Image(systemName: viewMode == .grid ? "list.bullet" : "square.grid.2x2")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.headerIcon)
            }
            .buttonStyle(.borderless)
            .help(viewMode == .grid ? "Switch to list view" : "Switch to grid view")

            // New item menu
            Menu {
                Button {
                    newItemIsFolder = false
                    newItemName = ""
                    isCreatingNewItem = true
                } label: {
                    Label("New File", systemImage: "doc")
                }
                Button {
                    newItemIsFolder = true
                    newItemName = ""
                    isCreatingNewItem = true
                } label: {
                    Label("New Folder", systemImage: "folder")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.headerIcon)
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.headerBackground)
    }

    // MARK: - New Item Field

    @ViewBuilder
    private var newItemField: some View {
        HStack(spacing: 6) {
            Image(systemName: newItemIsFolder ? "folder.badge.plus" : "doc.badge.plus")
                .font(.system(size: 11))
                .foregroundColor(Theme.accent)
            TextField(newItemIsFolder ? "Folder name..." : "File name...", text: $newItemName)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Theme.headerText)
                .onSubmit { commitNewItem() }
                .onKeyPress(.escape) {
                    isCreatingNewItem = false
                    return .handled
                }
            Button("Create") { commitNewItem() }
                .buttonStyle(.borderless)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.accent)
                .disabled(newItemName.isEmpty)
            Button {
                isCreatingNewItem = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundColor(Theme.headerIcon)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.headerBackground)
    }

    // MARK: - Grid View

    @ViewBuilder
    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 70))], spacing: 8) {
                ForEach(model.filteredItems) { item in
                    Button {
                        handleItemTap(item)
                    } label: {
                        VStack(spacing: 4) {
                            if item.isDirectory {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(Theme.accent)
                            } else {
                                Image(nsImage: item.icon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 28, height: 28)
                            }
                            Text(item.name)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Theme.headerText)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .truncationMode(.middle)
                        }
                        .frame(width: 70, height: 70)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Theme.appBackground.opacity(0.5))
                        )
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(8)
        }
    }

    // MARK: - List View

    @ViewBuilder
    private var listView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(model.filteredItems.enumerated()), id: \.element.id) { index, item in
                    Button {
                        handleItemTap(item)
                    } label: {
                        HStack(spacing: 8) {
                            if item.isDirectory {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(Theme.accent)
                                    .frame(width: 20)
                            } else {
                                Image(nsImage: item.icon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 16, height: 16)
                                    .frame(width: 20)
                            }
                            Text(item.name)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Theme.headerText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            if !item.isDirectory {
                                Text(formattedSize(item.fileSize))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(Theme.composePlaceholder)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(index % 2 == 0 ? Color.clear : Theme.appBackground.opacity(0.3))
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 28))
                .foregroundColor(Theme.headerIcon)
            Text(model.searchQuery.isEmpty ? "Empty directory" : "No matches")
                .font(.system(size: 12))
                .foregroundColor(Theme.composePlaceholder)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func handleItemTap(_ item: FileItem) {
        if item.isDirectory {
            model.navigateTo(item.path)
        } else {
            previewingFile = item.path
        }
    }

    private func commitNewItem() {
        guard !newItemName.isEmpty else { return }
        if newItemIsFolder {
            _ = model.createFolder(named: newItemName)
        } else {
            _ = model.createFile(named: newItemName)
        }
        isCreatingNewItem = false
    }

    private func formattedSize(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        let gb = mb / 1024
        return String(format: "%.1f GB", gb)
    }
}
