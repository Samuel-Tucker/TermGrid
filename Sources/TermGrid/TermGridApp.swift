import SwiftUI

@main
struct TermGridApp: App {
    @State private var store = WorkspaceStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        Window("TermGrid", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 600, minHeight: 400)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background || newPhase == .inactive {
                        store.flush()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    store.flush()
                }
        }
        .defaultSize(width: 900, height: 600)
    }
}
