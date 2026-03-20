import SwiftUI
import MarkdownUI

struct PopoutReaderView: View {
    let content: ExtractedContent
    let cellLabel: String
    let agentType: AgentType?
    let onDismiss: () -> Void
    var onRefresh: (() -> Void)? = nil
    let snapshotTime: Date

    @State private var showMarkdown = true

    init(content: ExtractedContent, cellLabel: String, agentType: AgentType?,
         onDismiss: @escaping () -> Void, onRefresh: (() -> Void)? = nil,
         snapshotTime: Date = Date()) {
        self.content = content
        self.cellLabel = cellLabel
        self.agentType = agentType
        self.onDismiss = onDismiss
        self.onRefresh = onRefresh
        self.snapshotTime = snapshotTime
    }

    private var timeString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: snapshotTime)
    }

    var body: some View {
        GeometryReader { geo in
            let panelWidth = min(geo.size.width * 0.8, 900)
            let panelMaxHeight = geo.size.height * 0.9

            VStack(spacing: 0) {
                // Header
                HStack(spacing: 10) {
                    // Cell label
                    Text(cellLabel.isEmpty ? "Terminal" : cellLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.headerText)

                    // Agent badge
                    if let agent = agentType {
                        HStack(spacing: 4) {
                            Image(systemName: agent.iconName)
                                .font(.system(size: 10))
                            Text(agent.displayName)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(agent.badgeColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(agent.badgeColor.opacity(0.15))
                        )
                    }

                    // Snapshot indicator (O5)
                    Text("Snapshot \(timeString)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.composePlaceholder)

                    if let onRefresh {
                        Button {
                            onRefresh()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                                .foregroundColor(Theme.headerIcon)
                        }
                        .buttonStyle(.plain)
                        .tooltip("Refresh snapshot")
                    }

                    Spacer()

                    // Raw / Markdown toggle
                    Picker("", selection: $showMarkdown) {
                        Text("MD").tag(true)
                        Text("Raw").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 100)

                    // Copy All button
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(content.text, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.headerIcon)
                    }
                    .buttonStyle(.plain)

                    // Close button
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.headerIcon)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().foregroundColor(Theme.divider)

                // Body
                ScrollView {
                    if showMarkdown {
                        Markdown(content.text)
                            .markdownTextStyle {
                                FontSize(13)
                                ForegroundColor(Theme.notesText)
                            }
                            .markdownBlockStyle(\.codeBlock) { config in
                                config.label
                                    .padding(12)
                                    .background(Theme.appBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .textSelection(.enabled)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    } else {
                        Text(content.text)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(Theme.notesText)
                            .textSelection(.enabled)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }

                // Truncation notice
                if content.wasTruncated {
                    Divider().foregroundColor(Theme.divider)
                    Text("Output truncated to \(content.lineCount) lines")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.composePlaceholder)
                        .padding(.vertical, 8)
                }
            }
            .frame(width: panelWidth)
            .frame(maxHeight: panelMaxHeight)
            .background(Theme.cellBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.cellBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onKeyPress(.escape) {
                onDismiss()
                return .handled
            }
        }
    }
}
