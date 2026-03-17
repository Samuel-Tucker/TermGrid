import SwiftUI
import AppKit

struct APIKeyCard: View {
    let entry: APIKeyEntry
    var onCopy: () -> Void
    var onReveal: () -> String?
    var onDelete: () -> Void

    @State private var isRevealed = false
    @State private var revealedKey: String?
    @State private var showCopied = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 0) {
            // Brand color stripe
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: entry.brandColor))
                .frame(width: 4)
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                // Service name
                Text(entry.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.headerText)

                // Masked or revealed key
                if isRevealed, let key = revealedKey {
                    Text(key)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.notesSecondary)
                        .textSelection(.enabled)
                } else {
                    Text("\u{2022}\u{2022}\u{2022}\u{2022}" + entry.maskedKey)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.notesSecondary)
                }

                // Env var name
                Text(entry.envVarName)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.composePlaceholder)
            }
            .padding(.leading, 10)

            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                // Copy button
                Button {
                    onCopy()
                    showCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showCopied = false
                    }
                } label: {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundColor(showCopied ? .green : Theme.headerIcon)
                }
                .buttonStyle(.plain)
                .help("Copy key")

                // Reveal toggle
                Button {
                    if isRevealed {
                        isRevealed = false
                        revealedKey = nil
                    } else {
                        revealedKey = onReveal()
                        isRevealed = revealedKey != nil
                    }
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.headerIcon)
                }
                .buttonStyle(.plain)
                .help(isRevealed ? "Hide key" : "Reveal key")

                // Delete button
                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.headerIcon)
                }
                .buttonStyle(.plain)
                .help("Delete key")
            }
            .padding(.trailing, 10)
        }
        .padding(.vertical, 8)
        .background(Theme.cellBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.cellBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .alert("Delete API Key?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove \"\(entry.name)\" from the vault.")
        }
    }
}
