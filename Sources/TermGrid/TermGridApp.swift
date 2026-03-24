import SwiftUI
import AppKit
import UserNotifications
import TermGridMLX

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
    @State private var collection = WorkspaceCollection()
    @State private var sessionManager = TerminalSessionManager()
    @State private var notificationSubsystem = NotificationSubsystem()
    @State private var vault = APIKeyVault()
    @State private var docsManager = DocsManager()
    @State private var completionEngine = CompletionEngine()
    @State private var mlxModelManager = ModelManager()
    @State private var mlxProvider: MLXCompletionProvider?
    @State private var skillsManager = SkillsManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        Window("TermGrid V5", id: "main") {
            ContentView(collection: collection, sessionManager: sessionManager, vault: vault,
                        docsManager: docsManager,
                        completionEngine: completionEngine,
                        skillsManager: skillsManager)
                .frame(minWidth: 600, minHeight: 400)
                .preferredColorScheme(.dark)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                    vault.onKeyRemoved = { keyID in
                        docsManager.removeDocsForKey(keyID)
                    }
                    collection.activeStore.sessionManager = sessionManager
                    startNotificationSubsystem()
                }
                .task {
                    try? await completionEngine.bootstrap()
                    let provider = MLXCompletionProvider(modelManager: mlxModelManager)
                    mlxProvider = provider
                    completionEngine.mlxProvider = provider
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background || newPhase == .inactive {
                        collection.flush(sessionManager: sessionManager)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    collection.flush(sessionManager: sessionManager)
                    vault.lock()
                    sessionManager.killAll()
                    notificationSubsystem.server?.stop()
                    mlxModelManager.unloadModel()
                }
                .onReceive(NotificationCenter.default.publisher(for: .commandPaletteDownloadMLXModel)) { _ in
                    mlxModelManager.downloadModel()
                }
                .onReceive(NotificationCenter.default.publisher(for: .commandPaletteRemoveMLXModel)) { _ in
                    mlxModelManager.removeModel()
                    mlxProvider?.isEnabled = false
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

        let manager = NotificationManager(sessionManager: sessionManager, collection: collection)
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
