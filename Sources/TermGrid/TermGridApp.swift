import SwiftUI
import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
    }
}

@MainActor
private final class NotificationSubsystem {
    var manager: NotificationManager?
    var server: SocketServer?
}

@main
struct TermGridApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = WorkspaceStore()
    @State private var sessionManager = TerminalSessionManager()
    @State private var notificationSubsystem = NotificationSubsystem()
    @State private var vault = APIKeyVault()
    @State private var docsManager = DocsManager()
    @State private var scrollbackManager = ScrollbackManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        Window("TermGrid", id: "main") {
            ContentView(store: store, sessionManager: sessionManager, vault: vault,
                        docsManager: docsManager, scrollbackManager: scrollbackManager)
                .frame(minWidth: 600, minHeight: 400)
                .preferredColorScheme(.dark)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                    vault.onKeyRemoved = { keyID in
                        docsManager.removeDocsForKey(keyID)
                    }
                    store.sessionManager = sessionManager
                    startNotificationSubsystem()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background || newPhase == .inactive {
                        store.flush()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    store.flush()
                    vault.lock()
                    sessionManager.killAll()
                    notificationSubsystem.server?.stop()
                }
        }
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Command Palette") {
                    NotificationCenter.default.post(name: .toggleCommandPalette, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Quick Terminal") {
                    NotificationCenter.default.post(name: .toggleFloatingPane, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }
        }
    }

    private func startNotificationSubsystem() {
        guard notificationSubsystem.manager == nil else { return }

        HookInstaller.installIfNeeded()
        HookInstaller.setupClaudeCodeHooks()
        HookInstaller.setupCodexHooks()

        let manager = NotificationManager(sessionManager: sessionManager, store: store)
        manager.setup()
        notificationSubsystem.manager = manager

        let server = SocketServer()
        server.start { payload in
            guard let signal = AgentSignal(from: payload) else { return }
            Task { @MainActor in
                manager.postNotification(for: signal)
            }
        }
        notificationSubsystem.server = server
    }
}
