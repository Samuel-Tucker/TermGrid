import SwiftUI

struct ContentView: View {
    @Bindable var store: WorkspaceStore

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
                    CellView(
                        cell: cell,
                        onUpdateLabel: { store.updateLabel($0, for: cell.id) },
                        onUpdateNotes: { store.updateNotes($0, for: cell.id) }
                    )
                    .frame(minHeight: 200)
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
