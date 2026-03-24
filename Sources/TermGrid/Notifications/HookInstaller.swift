import Foundation

enum HookInstaller {
    private static let hooksDir = NSHomeDirectory() + "/.termgrid/hooks"
    private static let versionFile = hooksDir + "/.version"
    private static let currentVersion = "3"

    static func installIfNeeded() {
        let fm = FileManager.default

        if let existingVersion = try? String(contentsOfFile: versionFile, encoding: .utf8),
           existingVersion.trimmingCharacters(in: .whitespacesAndNewlines) == currentVersion {
            return
        }

        try? fm.createDirectory(atPath: hooksDir, withIntermediateDirectories: true)

        let claudeHook = """
        #!/bin/bash
        PAYLOAD=$(cat)
        EVENT=$(echo "$PAYLOAD" | jq -r '.hook_event_name')

        if [ "$EVENT" = "Stop" ]; then
          MESSAGE=$(echo "$PAYLOAD" | jq -r '.last_assistant_message // ""')
          EVENT_TYPE="complete"
        elif [ "$EVENT" = "Start" ]; then
          MESSAGE=""
          EVENT_TYPE="started"
        else
          MESSAGE=$(echo "$PAYLOAD" | jq -r '.message // ""')
          EVENT_TYPE="needsInput"
        fi

        echo "{\\"cellID\\":\\"$TERMGRID_CELL_ID\\",\\"sessionType\\":\\"$TERMGRID_SESSION_TYPE\\",\\"agentType\\":\\"claudeCode\\",\\"eventType\\":\\"$EVENT_TYPE\\",\\"message\\":$(echo "$MESSAGE" | jq -Rs .)}" | nc -U ~/.termgrid/notify.sock
        """
        let claudePath = hooksDir + "/termgrid-notify-claude.sh"
        try? claudeHook.write(toFile: claudePath, atomically: true, encoding: .utf8)
        chmod(claudePath, 0o755)

        let codexHook = """
        #!/bin/bash
        PAYLOAD="$1"
        MESSAGE=$(echo "$PAYLOAD" | jq -r '.["last-assistant-message"] // ""')

        echo "{\\"cellID\\":\\"$TERMGRID_CELL_ID\\",\\"sessionType\\":\\"$TERMGRID_SESSION_TYPE\\",\\"agentType\\":\\"codex\\",\\"eventType\\":\\"complete\\",\\"message\\":$(echo "$MESSAGE" | jq -Rs .)}" | nc -U ~/.termgrid/notify.sock
        """
        let codexPath = hooksDir + "/termgrid-notify-codex.sh"
        try? codexHook.write(toFile: codexPath, atomically: true, encoding: .utf8)
        chmod(codexPath, 0o755)

        try? currentVersion.write(toFile: versionFile, atomically: true, encoding: .utf8)
    }

    private static func chmod(_ path: String, _ mode: mode_t) {
        Darwin.chmod(path, mode)
    }

    static var isJqInstalled: Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["jq"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    // MARK: - Agent Config Setup

    static func setupClaudeCodeHooks() {
        let settingsPath = NSHomeDirectory() + "/.claude/settings.json"
        let hookCommand = hooksDir + "/termgrid-notify-claude.sh"
        let fm = FileManager.default

        let claudeDir = NSHomeDirectory() + "/.claude"
        try? fm.createDirectory(atPath: claudeDir, withIntermediateDirectories: true)

        var settings: [String: Any] = [:]
        if let data = fm.contents(atPath: settingsPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = json
        }

        let hookEntry: [String: Any] = [
            "matcher": "*",
            "hooks": [["type": "command", "command": hookCommand]]
        ]

        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        for event in ["Stop", "Notification", "Start"] {
            var eventHooks = hooks[event] as? [[String: Any]] ?? []
            eventHooks.removeAll { entry in
                if let entryHooks = entry["hooks"] as? [[String: Any]] {
                    return entryHooks.contains { ($0["command"] as? String)?.contains("termgrid") == true }
                }
                return false
            }
            eventHooks.append(hookEntry)
            hooks[event] = eventHooks
        }

        settings["hooks"] = hooks

        if let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: settingsPath))
        }
    }

    static func setupCodexHooks() {
        let configPath = NSHomeDirectory() + "/.codex/config.toml"
        let hookCommand = hooksDir + "/termgrid-notify-codex.sh"
        let fm = FileManager.default

        let codexDir = NSHomeDirectory() + "/.codex"
        try? fm.createDirectory(atPath: codexDir, withIntermediateDirectories: true)

        var config = (try? String(contentsOfFile: configPath, encoding: .utf8)) ?? ""

        // Remove old [notify] table format (was a map, Codex expects an array)
        if config.contains("[notify]") {
            let lines = config.components(separatedBy: "\n")
            var filtered: [String] = []
            var inNotifySection = false
            for line in lines {
                if line.trimmingCharacters(in: .whitespaces) == "[notify]" {
                    inNotifySection = true
                    continue
                }
                if inNotifySection {
                    if line.hasPrefix("[") {
                        inNotifySection = false
                        filtered.append(line)
                    }
                    // Skip all lines in old [notify] section
                } else {
                    filtered.append(line)
                }
            }
            config = filtered.joined(separator: "\n")
        }

        // Remove any existing notify = ... line (array or string form)
        let lines = config.components(separatedBy: "\n")
        config = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("notify") || $0.contains("notify_") }.joined(separator: "\n")

        if !config.hasSuffix("\n") && !config.isEmpty { config += "\n" }
        // Codex expects notify as a TOML array of command strings
        config += "\nnotify = [\"\(hookCommand)\"]\n"

        try? config.write(toFile: configPath, atomically: true, encoding: .utf8)
    }
}
