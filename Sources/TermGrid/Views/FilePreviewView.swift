import SwiftUI
import AppKit

struct FilePreviewView: View {
    let filePath: String
    let model: FileExplorerModel
    let onBack: () -> Void

    @State private var content: String = ""
    @State private var editDraft: String = ""
    @State private var isEditing = false
    @State private var showUnsavedAlert = false
    @State private var isImage = false
    @State private var isBinary = false
    @State private var nsImage: NSImage? = nil

    private var fileName: String {
        (filePath as NSString).lastPathComponent
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Theme.divider.frame(height: 1)
            previewContent
        }
        .background(Theme.cellBackground)
        .onAppear {
            loadFile()
            // Auto-enter edit mode for new empty files
            if content.isEmpty && !isImage && !isBinary {
                editDraft = ""
                isEditing = true
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerBar: some View {
        HStack(spacing: 8) {
            Button {
                if isEditing && editDraft != content {
                    showUnsavedAlert = true
                } else {
                    onBack()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.accent)
            }
            .buttonStyle(.borderless)

            Text(fileName)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(Theme.headerText)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if !isImage && !isBinary {
                if isEditing {
                    Button("Cancel") {
                        isEditing = false
                        editDraft = content
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.headerIcon)

                    Button("Save") {
                        if model.writeFile(at: filePath, content: editDraft) {
                            content = editDraft
                            isEditing = false
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.accent)
                } else {
                    Button("Edit") {
                        editDraft = content
                        isEditing = true
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.accent)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.headerBackground)
        .alert("Unsaved Changes", isPresented: $showUnsavedAlert) {
            Button("Discard", role: .destructive) {
                isEditing = false
                editDraft = content
                onBack()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You have unsaved changes. Discard them?")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var previewContent: some View {
        if isImage {
            imagePreview
        } else if isBinary {
            binaryMessage
        } else if isEditing {
            FileEditorTextView(text: $editDraft)
        } else {
            readOnlyPreview
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let nsImage {
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(16)
            }
            .background(Theme.cellBackground)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.system(size: 32))
                    .foregroundColor(Theme.headerIcon)
                Text("Unable to load image")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.composePlaceholder)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var binaryMessage: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.zipper")
                .font(.system(size: 32))
                .foregroundColor(Theme.headerIcon)
            Text("Binary file — cannot display")
                .font(.system(size: 12))
                .foregroundColor(Theme.composePlaceholder)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var readOnlyPreview: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: 0) {
                // Line number gutter
                let lines = content.components(separatedBy: "\n")
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, _ in
                        Text("\(index + 1)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Theme.composePlaceholder)
                            .frame(height: 16)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
                .background(Theme.headerBackground)

                // Content
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Theme.notesText)
                            .frame(height: 16, alignment: .leading)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
        }
        .background(Theme.cellBackground)
    }

    // MARK: - Load

    private func loadFile() {
        if model.isImageFile(at: filePath) {
            isImage = true
            // Guard against huge images (>10 MB)
            let attrs = try? FileManager.default.attributesOfItem(atPath: filePath)
            let size = (attrs?[.size] as? Int64) ?? 0
            if size <= 10_000_000 {
                nsImage = NSImage(contentsOfFile: filePath)
            }
            return
        }

        if model.isBinaryFile(at: filePath) {
            isBinary = true
            return
        }

        if let text = model.readFile(at: filePath) {
            content = text
        } else {
            isBinary = true
        }
    }
}
