@testable import TermGrid
import Testing
import Foundation

@Suite("GitStatusModel Tests")
@MainActor
struct GitStatusModelTests {

    @Test func parseBranchName() {
        let output = """
        # branch.oid abc123
        # branch.head main
        1 .M N... 100644 100644 100644 abc def Sources/file.swift
        """
        let result = GitStatusModel.parseStatus(output)
        #expect(result.branch == "main")
    }

    @Test func parseDetachedHead() {
        let output = """
        # branch.oid abc123
        # branch.head (detached)
        """
        let result = GitStatusModel.parseStatus(output)
        #expect(result.branch == "(detached)")
    }

    @Test func parseStagedFiles() {
        let output = """
        # branch.head main
        1 A. N... 100644 100644 100644 abc def newfile.swift
        1 M. N... 100644 100644 100644 abc def modified.swift
        """
        let result = GitStatusModel.parseStatus(output)
        #expect(result.staged.count == 2)
        #expect(result.staged[0].path == "newfile.swift")
    }

    @Test func parseModifiedFiles() {
        let output = """
        # branch.head main
        1 .M N... 100644 100644 100644 abc def unstaged.swift
        """
        let result = GitStatusModel.parseStatus(output)
        #expect(result.modified.count == 1)
        #expect(result.modified[0].path == "unstaged.swift")
    }

    @Test func parseUntrackedFiles() {
        let output = """
        # branch.head main
        ? newfile.txt
        """
        let result = GitStatusModel.parseStatus(output)
        #expect(result.untracked.count == 1)
        #expect(result.untracked[0].path == "newfile.txt")
    }

    @Test func parseMixedStatus() {
        let output = """
        # branch.head feature/test
        1 A. N... 100644 100644 100644 abc def staged.swift
        1 .M N... 100644 100644 100644 abc def modified.swift
        1 AM N... 100644 100644 100644 abc def both.swift
        ? untracked.txt
        """
        let result = GitStatusModel.parseStatus(output)
        #expect(result.branch == "feature/test")
        #expect(result.staged.count == 2) // A. and AM
        #expect(result.modified.count == 2) // .M and AM
        #expect(result.untracked.count == 1)
    }

    @Test func parseEmptyRepo() {
        let output = """
        # branch.head main
        """
        let result = GitStatusModel.parseStatus(output)
        #expect(result.branch == "main")
        #expect(result.staged.isEmpty)
        #expect(result.modified.isEmpty)
        #expect(result.untracked.isEmpty)
    }

    @Test func parseRenamedFile() {
        let output = """
        # branch.head main
        2 R. N... 100644 100644 100644 abc def R100 new.swift\told.swift
        """
        let result = GitStatusModel.parseStatus(output)
        #expect(result.staged.count == 1)
        #expect(result.staged[0].path == "new.swift")
    }
}
