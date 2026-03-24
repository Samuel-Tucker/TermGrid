import Foundation
import Observation

/// Lightweight model for the notes sidebar pill list.
/// Lists .md files in .termgrid/notes/ and creates new notes.
/// NOT a full browser — no navigation, search, or editing (those live in ProjectNotesModel).
@MainActor
@Observable
final class SidebarNotesModel {
    struct NoteItem: Identifiable {
        let id: String // full path
        let name: String // display name (without .md extension)
        let path: String // full filesystem path
        let modifiedAt: Date
    }

    private(set) var notes: [NoteItem] = []
    private(set) var notesRoot: String = ""

    /// Refresh the notes list from .termgrid/notes/ for the given project directory.
    func loadNotes(baseDirectory: String) {
        let root = ProjectNotesModel.resolveNotesDirectory(for: baseDirectory)
        self.notesRoot = root

        let fm = FileManager.default
        guard fm.fileExists(atPath: root) else {
            notes = []
            return
        }

        do {
            let contents = try fm.contentsOfDirectory(atPath: root)
            var items: [NoteItem] = []
            for name in contents {
                guard name.hasSuffix(".md") else { continue }
                let fullPath = (root as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: fullPath, isDirectory: &isDir), !isDir.boolValue else { continue }

                let displayName = String(name.dropLast(3)) // strip .md
                let attrs = try? fm.attributesOfItem(atPath: fullPath)
                let modDate = attrs?[.modificationDate] as? Date ?? Date.distantPast

                items.append(NoteItem(id: fullPath, name: displayName, path: fullPath, modifiedAt: modDate))
            }
            // Sort by most recently modified first
            notes = items.sorted { $0.modifiedAt > $1.modifiedAt }
        } catch {
            notes = []
        }
    }

    /// Create a new .md note file. Returns the full path, or nil on failure.
    @discardableResult
    func createNote(named name: String, content: String = "", baseDirectory: String) -> String? {
        let root = ProjectNotesModel.resolveNotesDirectory(for: baseDirectory)
        let fm = FileManager.default

        // Ensure directory exists
        if !fm.fileExists(atPath: root) {
            try? fm.createDirectory(atPath: root, withIntermediateDirectories: true)
        }

        var filename = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if filename.isEmpty { return nil }
        if !filename.hasSuffix(".md") { filename += ".md" }

        let fullPath = (root as NSString).appendingPathComponent(filename)

        // Don't overwrite existing
        guard !fm.fileExists(atPath: fullPath) else { return nil }

        do {
            try content.write(toFile: fullPath, atomically: true, encoding: .utf8)
            loadNotes(baseDirectory: baseDirectory)
            return fullPath
        } catch {
            return nil
        }
    }
}
