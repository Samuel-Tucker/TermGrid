import Foundation
import Observation
import AppKit

@MainActor
@Observable
final class ProjectNotesModel {
    var baseDirectory: String
    var currentPath: String
    var items: [FileItem] = []
    var searchQuery: String = ""
    var notesDirectoryExists: Bool = false

    private static let maxItems = 500

    init(baseDirectory: String) {
        self.baseDirectory = baseDirectory
        let notesDir = Self.resolveNotesDirectory(for: baseDirectory)
        self.currentPath = notesDir
        self.notesDirectoryExists = FileManager.default.fileExists(atPath: notesDir)
    }

    // MARK: - Path Helpers

    static func resolveNotesDirectory(for base: String) -> String {
        (base as NSString).appendingPathComponent(".termgrid/notes")
    }

    var notesRoot: String {
        Self.resolveNotesDirectory(for: baseDirectory)
    }

    var pathComponents: [String] {
        guard currentPath.hasPrefix(notesRoot) else { return ["notes"] }
        let relative = String(currentPath.dropFirst(notesRoot.count))
        var parts = relative.split(separator: "/").map(String.init)
        parts.insert("notes", at: 0)
        return parts
    }

    var filteredItems: [FileItem] {
        guard !searchQuery.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
    }

    // MARK: - Directory Management

    @discardableResult
    func ensureNotesDirectory() -> Bool {
        let path = notesRoot
        if FileManager.default.fileExists(atPath: path) {
            notesDirectoryExists = true
            return true
        }
        do {
            try FileManager.default.createDirectory(
                atPath: path,
                withIntermediateDirectories: true
            )
            notesDirectoryExists = true
            currentPath = path
            loadContents()
            return true
        } catch {
            return false
        }
    }

    // MARK: - Loading

    func loadContents() {
        let url = URL(fileURLWithPath: currentPath)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            items = []
            return
        }

        var fileItems = contents.compactMap { url -> FileItem? in
            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let isDir = resourceValues?.isDirectory ?? false
            let size = Int64(resourceValues?.fileSize ?? 0)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            return FileItem(
                name: url.lastPathComponent,
                path: url.path,
                isDirectory: isDir,
                fileSize: size,
                icon: icon
            )
        }

        fileItems.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }

        if fileItems.count > Self.maxItems {
            fileItems = Array(fileItems.prefix(Self.maxItems))
        }

        items = fileItems
    }

    // MARK: - Navigation

    func navigateTo(_ path: String) {
        // Cannot navigate above notes root
        guard path.hasPrefix(notesRoot) else { return }
        currentPath = path
        searchQuery = ""
        loadContents()
    }

    var canNavigateBack: Bool {
        currentPath != notesRoot
    }

    func navigateBack() {
        guard canNavigateBack else { return }
        let parent = (currentPath as NSString).deletingLastPathComponent
        if parent.hasPrefix(notesRoot) {
            navigateTo(parent)
        } else {
            navigateTo(notesRoot)
        }
    }

    // MARK: - Create

    @discardableResult
    func createNote(named name: String) -> Bool {
        guard !name.contains("/"), !name.isEmpty else { return false }
        var fileName = name
        if (fileName as NSString).pathExtension.isEmpty {
            fileName += ".md"
        }
        let path = (currentPath as NSString).appendingPathComponent(fileName)
        guard !FileManager.default.fileExists(atPath: path) else { return false }
        let success = FileManager.default.createFile(atPath: path, contents: nil)
        if success { loadContents() }
        return success
    }

    @discardableResult
    func createFolder(named name: String) -> Bool {
        guard !name.contains("/"), !name.isEmpty else { return false }
        let path = (currentPath as NSString).appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: path) else { return false }
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
            loadContents()
            return true
        } catch {
            return false
        }
    }

    // MARK: - Read / Write

    func readNote(at path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        if data.count > 1_000_000 {
            let truncated = data.prefix(1_000_000)
            guard let text = String(data: truncated, encoding: .utf8) else { return nil }
            return text + "\n\n--- File truncated (>1 MB). Showing first portion only. ---"
        }
        return String(data: data, encoding: .utf8)
    }

    func writeNote(at path: String, content: String) -> Bool {
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }
}
