import SwiftUI

struct ContentView: View {
    @Bindable var store: WorkspaceStore
    var sessionManager: TerminalSessionManager

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 12),
            count: store.workspace.gridLayout.columns
        )
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(store.workspace.visibleCells) { cell in
                    let session = sessionManager.session(for: cell.id)
                    CellView(
                        cell: cell,
                        session: session,
                        onUpdateLabel: { store.updateLabel($0, for: cell.id) },
                        onUpdateNotes: { store.updateNotes($0, for: cell.id) },
                        onUpdateWorkingDirectory: { newPath in
                            store.updateWorkingDirectory(newPath, for: cell.id)
                            sessionManager.createSession(for: cell.id, workingDirectory: newPath)
                        },
                        onRestartSession: {
                            sessionManager.createSession(for: cell.id, workingDirectory: cell.workingDirectory)
                        }
                    )
                    .frame(minHeight: 200)
                    .onAppear {
                        if sessionManager.session(for: cell.id) == nil {
                            sessionManager.createSession(for: cell.id, workingDirectory: cell.workingDirectory)
                        }
                    }
                }
            }
            .padding(16)
        }
        .toolbar {
            ToolbarItem {
                GridPickerView(selection: Binding(
                    get: { store.workspace.gridLayout },
                    set: { store.setGridPreset($0) }
                ))
            }
        }
    }
}
