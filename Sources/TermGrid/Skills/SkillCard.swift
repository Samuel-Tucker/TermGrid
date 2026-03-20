import SwiftUI

struct SkillCard: View {
    let skill: Skill
    @Binding var isExpanded: Bool
    let onSend: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteAlert = false

    private var categoryColor: Color {
        switch skill.category {
        case .prompt: return Color(hex: "#D4A574") // amber
        case .shell:  return Color(hex: "#75BE95") // green
        case .code:   return Color(hex: "#A78BFA") // purple
        case .custom: return Color(hex: "#7A756B") // grey
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(categoryColor)
                    .frame(width: 4, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.headerText)
                        .lineLimit(1)

                    if !skill.description.isEmpty {
                        Text(skill.description)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.notesSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button(action: onSend) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.accent)
                }
                .buttonStyle(.plain)
                .tooltip("Send to Phantom Compose")
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            // Tags row
            if !skill.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(skill.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(Theme.notesSecondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Theme.cellBackground)
                                )
                        }
                    }
                    .padding(.horizontal, 22)
                }
                .padding(.bottom, 6)
            }

            // Expanded content
            if isExpanded {
                Divider().foregroundColor(Theme.divider)

                ScrollView {
                    Text(skill.content)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Theme.headerText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 200)

                HStack(spacing: 12) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(skill.content, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.notesSecondary)

                    Button(action: onEdit) {
                        Label("Edit", systemImage: "pencil")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.notesSecondary)

                    Button { showDeleteAlert = true } label: {
                        Label("Delete", systemImage: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.error)

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.cellBackground)
        )
        .alert("Delete Skill", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: onDelete)
        } message: {
            Text("Are you sure you want to delete \"\(skill.name)\"?")
        }
    }
}
