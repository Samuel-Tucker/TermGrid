import Foundation
import Observation
import AppKit

struct FileItem: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    let fileSize: Int64
    let icon: NSImage

    var isHidden: Bool { name.hasPrefix(".") }
}

@MainActor
@Observable
final class FileExplorerModel {
    var currentPath: String
    var items: [FileItem] = []
    var searchQuery: String = ""
    var showHiddenFiles: Bool = false

    private let rootPath: String
    private static let maxItems = 500
    private static var iconCache: [String: NSImage] = [:]

    init(rootPath: String) {
        self.rootPath = rootPath
        self.currentPath = rootPath
    }

    var filteredItems: [FileItem] {
        guard !searchQuery.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
    }

    var pathComponents: [String] {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        var display = currentPath
        if display.hasPrefix(homePath) {
            display = "~" + display.dropFirst(homePath.count)
        }
        return display.split(separator: "/").map(String.init)
    }

    var shortenedPath: String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        if currentPath.hasPrefix(homePath) {
            return "~" + currentPath.dropFirst(homePath.count)
        }
        return currentPath
    }

    func loadContents() {
        let url = URL(fileURLWithPath: currentPath)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: showHiddenFiles ? [] : [.skipsHiddenFiles]
        ) else {
            items = []
            return
        }

        var fileItems = contents.compactMap { url -> FileItem? in
            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let isDir = resourceValues?.isDirectory ?? false
            let size = Int64(resourceValues?.fileSize ?? 0)
            let icon = Self.cachedIcon(for: url, isDirectory: isDir)
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

    func navigateTo(_ path: String) {
        currentPath = path
        searchQuery = ""
        loadContents()
    }

    func navigateBack() {
        let parent = (currentPath as NSString).deletingLastPathComponent
        if parent.count >= rootPath.count {
            navigateTo(parent)
        }
    }

    func navigateToBreadcrumbIndex(_ index: Int) {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        if currentPath.hasPrefix(homePath) {
            let relative = String(currentPath.dropFirst(homePath.count))
            let components = relative.split(separator: "/").map(String.init)
            let targetComponents = Array(components.prefix(index + 1))
            let targetPath = homePath + "/" + targetComponents.joined(separator: "/")
            navigateTo(targetPath)
        } else {
            let parts = currentPath.split(separator: "/").map(String.init)
            let targetPath = "/" + parts.prefix(index + 1).joined(separator: "/")
            navigateTo(targetPath)
        }
    }

    func createFile(named name: String) -> Bool {
        guard !name.contains("/"), !name.isEmpty else { return false }
        let path = (currentPath as NSString).appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: path) else { return false }
        let success = FileManager.default.createFile(atPath: path, contents: nil)
        if success { loadContents() }
        return success
    }

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

    func readFile(at path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        if data.count > 1_000_000 {
            let truncated = data.prefix(1_000_000)
            guard let text = String(data: truncated, encoding: .utf8) else { return nil }
            return text + "\n\n--- File truncated (>1 MB). Showing first portion only. ---"
        }
        return String(data: data, encoding: .utf8)
    }

    func writeFile(at path: String, content: String) -> Bool {
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    func isImageFile(at path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "webp", "heic", "svg"].contains(ext)
    }

    func isBinaryFile(at path: String) -> Bool {
        guard let data = FileManager.default.contents(atPath: path)?.prefix(512) else { return true }
        return data.contains(0)
    }

    private static func cachedIcon(for url: URL, isDirectory: Bool) -> NSImage {
        if isDirectory {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        let ext = url.pathExtension
        if let cached = iconCache[ext] {
            return cached
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[ext] = icon
        return icon
    }
}
