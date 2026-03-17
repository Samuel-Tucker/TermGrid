// Sources/TermGrid/CommandPalette/CommandPaletteView.swift
import SwiftUI

struct CommandPaletteView: View {
    let registry: CommandRegistry
    let context: CommandContext
    let onDismiss: () -> Void

    @State private var searchQuery = ""
    @State private var selectedIndex = 0

    private var filteredCommands: [AppCommand] {
        let available = registry.availableCommands(for: context)
        guard !searchQuery.isEmpty else { return available }
        return available.filter {
            $0.title.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Context header
            HStack {
                if let cellID = context.focusedCellID,
                   let cell = context.store.workspace.visibleCells.first(where: { $0.id == cellID }) {
                    Text("Cell: \(cell.label.isEmpty ? "Untitled" : cell.label)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.accent)
                } else {
                    Text("Global")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.headerIcon)
                }
                Spacer()
                Text("⌘⇧P")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.composePlaceholder)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.composePlaceholder)
                TextField("Type a command...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.headerText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.headerBackground)

            Theme.divider.frame(height: 1)

            // Command list
            if filteredCommands.isEmpty {
                VStack(spacing: 6) {
                    Text("No matching commands")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.composePlaceholder)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { index, command in
                                commandRow(command, isSelected: index == selectedIndex)
                                    .id(command.id)
                                    .onTapGesture {
                                        executeCommand(command)
                                    }
                            }
                        }
                    }
                    .frame(maxHeight: 250)
                    .onChange(of: selectedIndex) { _, newIndex in
                        if newIndex < filteredCommands.count {
                            proxy.scrollTo(filteredCommands[newIndex].id)
                        }
                    }
                }
            }
        }
        .frame(width: 400)
        .frame(maxHeight: 300)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.cellBackground)
                .shadow(color: .black.opacity(0.5), radius: 20)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.cellBorder, lineWidth: 1)
        )
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 { selectedIndex -= 1 }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < filteredCommands.count - 1 { selectedIndex += 1 }
            return .handled
        }
        .onKeyPress(.return) {
            if selectedIndex < filteredCommands.count {
                executeCommand(filteredCommands[selectedIndex])
            }
            return .handled
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .onChange(of: searchQuery) { _, _ in
            selectedIndex = 0
        }
    }

    @ViewBuilder
    private func commandRow(_ command: AppCommand, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: command.icon)
                .font(.system(size: 12))
                .foregroundColor(isSelected ? Theme.accent : Theme.headerIcon)
                .frame(width: 20)

            Text(command.title)
                .font(.system(size: 12))
                .foregroundColor(Theme.headerText)

            Spacer()

            Text(command.scope == .global ? "Global" : "Cell")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Theme.composePlaceholder)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(Theme.cellBorder)
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Theme.accent.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
    }

    private func executeCommand(_ command: AppCommand) {
        command.action(context)
        onDismiss()
    }
}
