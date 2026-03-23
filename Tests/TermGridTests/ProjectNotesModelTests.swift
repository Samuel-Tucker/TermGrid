@testable import TermGrid
import Testing
import Foundation

@Suite("ProjectNotesModel Tests")
@MainActor
struct ProjectNotesModelTests {

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermGridTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func resolveNotesDirectoryReturnsCorrectPath() {
        let path = ProjectNotesModel.resolveNotesDirectory(for: "/Users/test/project")
        #expect(path == "/Users/test/project/.termgrid/notes")
    }

    @Test func ensureNotesDirectoryCreatesDirectory() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let model = ProjectNotesModel(baseDirectory: dir.path)
        #expect(!model.notesDirectoryExists)
        let result = model.ensureNotesDirectory()
        #expect(result)
        #expect(model.notesDirectoryExists)
        #expect(FileManager.default.fileExists(atPath: model.notesRoot))
    }

    @Test func notesDirectoryExistsIsFalseWhenMissing() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let model = ProjectNotesModel(baseDirectory: dir.path)
        #expect(!model.notesDirectoryExists)
    }

    @Test func notesDirectoryExistsAfterEnsure() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let model = ProjectNotesModel(baseDirectory: dir.path)
        _ = model.ensureNotesDirectory()
        #expect(model.notesDirectoryExists)
    }

    @Test func createNoteCreatesMDFile() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let model = ProjectNotesModel(baseDirectory: dir.path)
        _ = model.ensureNotesDirectory()
        let result = model.createNote(named: "test.md")
        #expect(result)
        let expected = (model.notesRoot as NSString).appendingPathComponent("test.md")
        #expect(FileManager.default.fileExists(atPath: expected))
    }

    @Test func createNoteAutoAppendsMD() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let model = ProjectNotesModel(baseDirectory: dir.path)
        _ = model.ensureNotesDirectory()
        let result = model.createNote(named: "ideas")
        #expect(result)
        let expected = (model.notesRoot as NSString).appendingPathComponent("ideas.md")
        #expect(FileManager.default.fileExists(atPath: expected))
    }

    @Test func createFolderCreatesDirectory() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let model = ProjectNotesModel(baseDirectory: dir.path)
        _ = model.ensureNotesDirectory()
        let result = model.createFolder(named: "subfolder")
        #expect(result)
        let expected = (model.notesRoot as NSString).appendingPathComponent("subfolder")
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: expected, isDirectory: &isDir))
        #expect(isDir.boolValue)
    }

    @Test func navigateToAndBack() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let model = ProjectNotesModel(baseDirectory: dir.path)
        _ = model.ensureNotesDirectory()
        _ = model.createFolder(named: "sub")

        let subPath = (model.notesRoot as NSString).appendingPathComponent("sub")
        model.navigateTo(subPath)
        #expect(model.currentPath == subPath)

        model.navigateBack()
        #expect(model.currentPath == model.notesRoot)
    }

    @Test func cannotNavigateAboveNotesRoot() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let model = ProjectNotesModel(baseDirectory: dir.path)
        _ = model.ensureNotesDirectory()

        // At root, canNavigateBack should be false
        #expect(!model.canNavigateBack)

        // Try to navigate above root
        model.navigateTo(dir.path)
        #expect(model.currentPath == model.notesRoot)
    }

    @Test func loadContentsListsFiles() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let model = ProjectNotesModel(baseDirectory: dir.path)
        _ = model.ensureNotesDirectory()
        _ = model.createNote(named: "note1")
        _ = model.createNote(named: "note2")
        _ = model.createFolder(named: "folder1")

        model.loadContents()
        #expect(model.items.count == 3)
        // Folders should come first
        #expect(model.items.first?.isDirectory == true)
    }

    @Test func readWriteNote() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let model = ProjectNotesModel(baseDirectory: dir.path)
        _ = model.ensureNotesDirectory()
        _ = model.createNote(named: "test.md")
        let path = (model.notesRoot as NSString).appendingPathComponent("test.md")

        let writeResult = model.writeNote(at: path, content: "Hello World")
        #expect(writeResult)

        let content = model.readNote(at: path)
        #expect(content == "Hello World")
    }
}
