import SwiftUI

struct ComposeHistoryPopup: View {
    let history: [ComposeHistoryEntry]
    let query: String
    let selectedIndex: Int
    let onSelect: (String) -> Void
    let onDismiss: () -> Void

    private var filteredEntries: [(entry: ComposeHistoryEntry, matchIndices: [String.Index]?)] {
        // Show newest first
        let reversed = history.reversed()
        if query.isEmpty {
            return reversed.map { ($0, nil) }
        }
        return reversed.compactMap { entry in
            if let indices = fuzzyMatch(query: query, in: entry.content) {
                return (entry, indices)
            }
            return nil
        }
    }

    var body: some View {
        let entries = filteredEntries
        if entries.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 0) {
                // Show max 5 entries
                let visible = Array(entries.prefix(5))
                ForEach(Array(visible.enumerated()), id: \.element.entry.id) { index, item in
                    historyRow(entry: item.entry, matchIndices: item.matchIndices,
                               isSelected: index == selectedIndex)
                    .onTapGesture {
                        onSelect(item.entry.content)
                    }
                }

                // Count indicator if more results hidden
                if entries.count > 5 {
                    HStack {
                        Spacer()
                        Text("\(entries.count - 5) more...")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(Theme.composeChrome)
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }
            .background(Theme.composeBackground.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Theme.phantomDivider.opacity(0.4), lineWidth: 1)
            )
            .padding(.horizontal, 4)
            .padding(.bottom, 2)
        }
    }

    @ViewBuilder
    private func historyRow(entry: ComposeHistoryEntry, matchIndices: [String.Index]?,
                            isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            // Title with fuzzy-match highlighting
            highlightedText(entry.displayTitle, matchIndices: matchIndices, fullContent: entry.content)
                .lineLimit(1)

            if entry.lineCount > 1 {
                Text("[\(entry.lineCount) lines]")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.composeChrome)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.cellBorder)
                    )
            }

            Spacer()

            Text(entry.relativeTimestamp)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Theme.historyTimestamp)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isSelected ? Theme.historyRowSelected : Color.clear)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func highlightedText(_ title: String, matchIndices: [String.Index]?,
                                 fullContent: String) -> some View {
        if let indices = matchIndices {
            // Map match indices from fullContent space to displayTitle space
            let titleStartIndex = title.startIndex
            let contentStartIndex = fullContent.startIndex

            // Build highlighted text by iterating through the title characters
            let matchSet = Set(indices)
            let parts = title.indices.map { idx -> (Character, Bool) in
                let offset = title.distance(from: titleStartIndex, to: idx)
                let contentIdx = fullContent.index(contentStartIndex, offsetBy: offset, limitedBy: fullContent.endIndex) ?? fullContent.endIndex
                let isMatch = contentIdx < fullContent.endIndex && matchSet.contains(contentIdx)
                return (title[idx], isMatch)
            }

            // Build Text by concatenation
            parts.reduce(Text("")) { result, part in
                result + Text(String(part.0))
                    .foregroundColor(part.1 ? Theme.accent : Theme.headerText)
            }
            .font(.system(size: 11, design: .monospaced))
        } else {
            Text(title)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Theme.headerText)
        }
    }
}
