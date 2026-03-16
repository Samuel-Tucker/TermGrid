import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Set dock icon from bundled resource
        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
    }
}

@main
struct TermGridApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = WorkspaceStore()
    @State private var sessionManager = TerminalSessionManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        Window("TermGrid", id: "main") {
            ContentView(store: store, sessionManager: sessionManager)
                .frame(minWidth: 600, minHeight: 400)
                .preferredColorScheme(.dark)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    // Only flush persistence on background/inactive — do NOT kill sessions
                    if newPhase == .background || newPhase == .inactive {
                        store.flush()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    store.flush()
                    sessionManager.killAll()
                }
        }
        .defaultSize(width: 900, height: 600)
    }
}
