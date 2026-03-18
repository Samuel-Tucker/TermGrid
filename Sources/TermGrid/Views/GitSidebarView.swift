import SwiftUI
import AppKit

struct GitSidebarView: View {
    let cellID: UUID
    @Bindable var model: GitStatusModel
    let onFileClick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !model.result.isRepo {
                notARepoView
            } else {
                branchHeader
                if let state = model.result.mergeState {
                    stateBanner(state)
                }
                Theme.divider.frame(height: 1)
                fileList
                Theme.divider.frame(height: 1)
                quickActions
            }
        }
        .background(Theme.notesBackground)
    }

    @ViewBuilder
    private var notARepoView: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 24))
                .foregroundColor(Theme.headerIcon)
            Text("Not a git repository")
                .font(.system(size: 11))
                .foregroundColor(Theme.composePlaceholder)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var branchHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 10))
                .foregroundColor(Theme.accent)
            Text(model.result.branch)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(Theme.headerText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.result.branch, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 9))
                    .foregroundColor(Theme.headerIcon)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func stateBanner(_ state: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
            Text(state)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(Theme.accent)
    }

    @ViewBuilder
    private var fileList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !model.result.staged.isEmpty {
                    sectionHeader("STAGED", color: Theme.staged)
                    ForEach(model.result.staged) { file in
                        fileRow(file, color: Theme.staged)
                    }
                }
                if !model.result.modified.isEmpty {
                    sectionHeader("MODIFIED", color: Theme.accent)
                    ForEach(model.result.modified) { file in
                        fileRow(file, color: Theme.accent)
                    }
                }
                if !model.result.untracked.isEmpty {
                    sectionHeader("UNTRACKED", color: Theme.headerIcon)
                    ForEach(model.result.untracked) { file in
                        fileRow(file, color: Theme.headerIcon)
                    }
                }
                if model.result.staged.isEmpty && model.result.modified.isEmpty && model.result.untracked.isEmpty {
                    Text("Working tree clean")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.composePlaceholder)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    @ViewBuilder
    private func fileRow(_ file: GitFileEntry, color: Color) -> some View {
        Button {
            onFileClick(file.path)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text((file.path as NSString).lastPathComponent)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.notesText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private var quickActions: some View {
        HStack(spacing: 8) {
            Button("Stage All") { model.stageAll() }
                .buttonStyle(.borderless)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.staged)
                .disabled(model.result.modified.isEmpty && model.result.untracked.isEmpty)

            Button("Unstage All") { model.unstageAll() }
                .buttonStyle(.borderless)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.accent)
                .disabled(model.result.staged.isEmpty)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
