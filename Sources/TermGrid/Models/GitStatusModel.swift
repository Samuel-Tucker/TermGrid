import Foundation
import Observation

struct GitFileEntry: Identifiable {
    let id = UUID()
    let path: String
    let status: String
}

struct GitStatusResult {
    var branch: String = ""
    var staged: [GitFileEntry] = []
    var modified: [GitFileEntry] = []
    var untracked: [GitFileEntry] = []
    var mergeState: String? = nil
    var isRepo: Bool = true
}

@MainActor
@Observable
final class GitStatusModel {
    var result = GitStatusResult()
    var isLoading = false

    private var repoRoot: String?
    private var gitDir: String?
    private var pollTask: Task<Void, Never>?
    private var sequenceNumber: Int = 0
    private var inFlight = false
    private let gitPath = "/usr/bin/git"
    private var directory: String = ""

    func setDirectory(_ path: String) {
        guard path != directory else { return }
        directory = path
        repoRoot = nil
        gitDir = nil
        stopPolling()
        resolveRepo()
    }

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func resolveRepo() {
        Task {
            let topLevel = await runGit(["-C", directory, "rev-parse", "--show-toplevel"])
            if let root = topLevel?.trimmingCharacters(in: .whitespacesAndNewlines), !root.isEmpty {
                repoRoot = root
                let gd = await runGit(["-C", directory, "rev-parse", "--git-dir"])
                if let dir = gd?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    if dir.hasPrefix("/") {
                        gitDir = dir
                    } else {
                        gitDir = (root as NSString).appendingPathComponent(dir)
                    }
                }
                result.isRepo = true
                await poll()
            } else {
                result = GitStatusResult()
                result.isRepo = false
            }
        }
    }

    private func poll() async {
        guard let repoRoot, !inFlight else { return }
        inFlight = true
        sequenceNumber += 1
        let mySequence = sequenceNumber

        let output = await runGit(["-C", repoRoot, "status", "--porcelain=v2", "--branch"])
        guard mySequence == sequenceNumber else {
            inFlight = false
            return
        }

        if let output {
            var parsed = Self.parseStatus(output)
            if let gitDir {
                parsed.mergeState = Self.detectMergeState(gitDir: gitDir)
            }
            result = parsed
        }
        inFlight = false
    }

    // MARK: - Parsing (static for testability)

    static func parseStatus(_ output: String) -> GitStatusResult {
        var result = GitStatusResult()
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            if line.hasPrefix("# branch.head ") {
                result.branch = String(line.dropFirst("# branch.head ".count))
            } else if line.hasPrefix("1 ") || line.hasPrefix("2 ") {
                let parts = line.components(separatedBy: " ")
                guard parts.count >= 9 else { continue }
                let xy = parts[1]
                let x = xy.prefix(1)
                let y = xy.suffix(1)

                var path: String
                if line.hasPrefix("2 ") {
                    // Type-2 format: "2 XY sub mH mI mW hH hI score paths"
                    // parts[8] is the score (e.g. "R100"), paths are in parts[9+] separated by \t
                    guard parts.count >= 10 else { continue }
                    let pathsField = parts[9...].joined(separator: " ")
                    path = pathsField.components(separatedBy: "\t").first ?? pathsField
                } else {
                    path = parts[8...].joined(separator: " ")
                }

                if x != "." && x != "?" {
                    result.staged.append(GitFileEntry(path: path, status: String(x)))
                }
                if y != "." && y != "?" {
                    result.modified.append(GitFileEntry(path: path, status: String(y)))
                }
            } else if line.hasPrefix("? ") {
                let path = String(line.dropFirst(2))
                result.untracked.append(GitFileEntry(path: path, status: "?"))
            }
        }
        return result
    }

    static func detectMergeState(gitDir: String) -> String? {
        let fm = FileManager.default
        if fm.fileExists(atPath: (gitDir as NSString).appendingPathComponent("MERGE_HEAD")) {
            return "MERGING"
        }
        let rebaseMerge = (gitDir as NSString).appendingPathComponent("rebase-merge")
        if fm.fileExists(atPath: rebaseMerge) {
            let msgnum = (try? String(contentsOfFile: (rebaseMerge as NSString).appendingPathComponent("msgnum")))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "?"
            let end = (try? String(contentsOfFile: (rebaseMerge as NSString).appendingPathComponent("end")))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "?"
            return "REBASING \(msgnum)/\(end)"
        }
        if fm.fileExists(atPath: (gitDir as NSString).appendingPathComponent("rebase-apply")) {
            return "REBASING"
        }
        return nil
    }

    // MARK: - Quick Actions

    func stageAll() {
        guard let repoRoot else { return }
        Task {
            _ = await runGit(["-C", repoRoot, "add", "-A"])
            await poll()
        }
    }

    func unstageAll() {
        guard let repoRoot else { return }
        Task {
            let headCheck = await runGit(["-C", repoRoot, "rev-parse", "HEAD"])
            if headCheck == nil || headCheck?.contains("fatal") == true {
                _ = await runGit(["-C", repoRoot, "rm", "--cached", "-r", "."])
            } else {
                let cached = await runGit(["-C", repoRoot, "diff", "--cached", "--name-only", "--diff-filter=d"])
                if let files = cached?.components(separatedBy: "\n").filter({ !$0.isEmpty }), !files.isEmpty {
                    _ = await runGit(["-C", repoRoot, "restore", "--staged", "--"] + files)
                }
            }
            await poll()
        }
    }

    // MARK: - Git Process

    private func runGit(_ args: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: gitPath)
            process.arguments = args
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if process.terminationStatus == 0 {
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                } else {
                    continuation.resume(returning: nil)
                }
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}
