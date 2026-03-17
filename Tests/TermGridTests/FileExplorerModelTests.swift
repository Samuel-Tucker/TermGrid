@testable import TermGrid
import Foundation
import Testing

@Suite("FileExplorerModel Tests")
@MainActor
struct FileExplorerModelTests {

    private func makeTempDir() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermGridTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: tmp.appendingPathComponent("Sources"), withIntermediateDirectories: false)
        try FileManager.default.createDirectory(
            at: tmp.appendingPathComponent(".git"), withIntermediateDirectories: false)
        try "hello".write(to: tmp.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "{}".write(to: tmp.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try "secret".write(to: tmp.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        return tmp
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test func loadsDirectoryContents() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let model = FileExplorerModel(rootPath: dir.path)
        model.loadContents()
        #expect(model.items.count == 3)
    }

    @Test func foldersBeforeFiles() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let model = FileExplorerModel(rootPath: dir.path)
        model.loadContents()
        let firstItem = model.items.first
        #expect(firstItem?.isDirectory == true)
        #expect(firstItem?.name == "Sources")
    }

    @Test func showHiddenFilesToggle() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let model = FileExplorerModel(rootPath: dir.path)
        model.loadContents()
        let countWithout = model.items.count
        model.showHiddenFiles = true
        model.loadContents()
        #expect(model.items.count > countWithout)
    }

    @Test func searchFilters() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let model = FileExplorerModel(rootPath: dir.path)
        model.loadContents()
        model.searchQuery = "READ"
        #expect(model.filteredItems.count == 1)
        #expect(model.filteredItems.first?.name == "README.md")
    }

    @Test func navigateIntoSubdirectory() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let model = FileExplorerModel(rootPath: dir.path)
        model.loadContents()
        model.navigateTo(dir.appendingPathComponent("Sources").path)
        #expect(model.currentPath == dir.appendingPathComponent("Sources").path)
        #expect(model.pathComponents.last == "Sources")
    }

    @Test func navigateBack() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let model = FileExplorerModel(rootPath: dir.path)
        model.loadContents()
        model.navigateTo(dir.appendingPathComponent("Sources").path)
        model.navigateBack()
        #expect(model.currentPath == dir.path)
    }

    @Test func navigateToBreadcrumb() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let model = FileExplorerModel(rootPath: dir.path)
        model.navigateTo(dir.appendingPathComponent("Sources").path)
        model.navigateTo(dir.path)
        #expect(model.currentPath == dir.path)
    }

    @Test func effectiveDirectoryFallback() {
        let model = FileExplorerModel(rootPath: "/tmp/test")
        #expect(model.currentPath == "/tmp/test")
    }

    @Test func createNewFile() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let model = FileExplorerModel(rootPath: dir.path)
        model.loadContents()
        let result = model.createFile(named: "new.txt")
        #expect(result == true)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("new.txt").path))
    }

    @Test func createNewFolder() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let model = FileExplorerModel(rootPath: dir.path)
        model.loadContents()
        let result = model.createFolder(named: "NewFolder")
        #expect(result == true)
        var isDir: ObjCBool = false
        FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("NewFolder").path, isDirectory: &isDir)
        #expect(isDir.boolValue == true)
    }

    @Test func createDuplicateFileFails() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let model = FileExplorerModel(rootPath: dir.path)
        model.loadContents()
        let result = model.createFile(named: "README.md")
        #expect(result == false)
    }

    @Test func createFileWithSlashFails() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let model = FileExplorerModel(rootPath: dir.path)
        let result = model.createFile(named: "bad/name.txt")
        #expect(result == false)
    }

    @Test func readFileReturnsContent() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let model = FileExplorerModel(rootPath: dir.path)
        let content = model.readFile(at: dir.appendingPathComponent("README.md").path)
        #expect(content == "hello")
    }

    @Test func readFileBinaryReturnsNil() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let binaryPath = dir.appendingPathComponent("binary.dat")
        try Data([0x00, 0x01, 0x02, 0xFF]).write(to: binaryPath)
        let model = FileExplorerModel(rootPath: dir.path)
        let content = model.readFile(at: binaryPath.path)
        #expect(content == nil)
    }

    @Test func writeFileWorks() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let model = FileExplorerModel(rootPath: dir.path)
        let path = dir.appendingPathComponent("new.txt").path
        _ = model.createFile(named: "new.txt")
        let result = model.writeFile(at: path, content: "written")
        #expect(result == true)
        let readBack = model.readFile(at: path)
        #expect(readBack == "written")
    }

    @Test func isImageFileDetectsExtensions() {
        let model = FileExplorerModel(rootPath: "/tmp")
        #expect(model.isImageFile(at: "/foo/photo.png") == true)
        #expect(model.isImageFile(at: "/foo/photo.JPG") == true)
        #expect(model.isImageFile(at: "/foo/code.swift") == false)
    }

    @Test func isBinaryFileDetectsNullBytes() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let binaryPath = dir.appendingPathComponent("binary.dat")
        try Data([0x00, 0x01, 0x02]).write(to: binaryPath)
        let model = FileExplorerModel(rootPath: dir.path)
        #expect(model.isBinaryFile(at: binaryPath.path) == true)
        #expect(model.isBinaryFile(at: dir.appendingPathComponent("README.md").path) == false)
    }
}
