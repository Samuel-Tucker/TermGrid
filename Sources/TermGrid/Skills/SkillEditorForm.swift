import SwiftUI

struct SkillEditorForm: View {
    var existingSkill: Skill?
    let onSave: (Skill) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var content: String = ""
    @State private var category: SkillCategory = .prompt
    @State private var tagsText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(existingSkill != nil ? "Edit Skill" : "New Skill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.headerText)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            TextField("Description (optional)", text: $description)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            Text("Content")
                .font(.system(size: 11))
                .foregroundColor(Theme.notesSecondary)

            TextEditor(text: $content)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 80, maxHeight: 150)
                .scrollContentBackground(.hidden)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.appBackground)
                )

            Picker("Category", selection: $category) {
                ForEach(SkillCategory.allCases, id: \.self) { cat in
                    Text(cat.displayName).tag(cat)
                }
            }
            .pickerStyle(.segmented)
            .font(.system(size: 11))

            TextField("Tags (comma-separated)", text: $tagsText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.notesSecondary)
                    .font(.system(size: 12))

                Spacer()

                Button("Save") {
                    let tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    let now = Date()
                    let skill = Skill(
                        id: existingSkill?.id ?? UUID(),
                        name: name,
                        description: description,
                        content: content,
                        category: category,
                        tags: tags,
                        createdAt: existingSkill?.createdAt ?? now,
                        updatedAt: now
                    )
                    onSave(skill)
                }
                .buttonStyle(.plain)
                .foregroundColor(name.isEmpty || content.isEmpty ? Theme.accentDisabled : Theme.accent)
                .font(.system(size: 12, weight: .semibold))
                .disabled(name.isEmpty || content.isEmpty)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.headerBackground)
        )
        .onAppear {
            if let skill = existingSkill {
                name = skill.name
                description = skill.description
                content = skill.content
                category = skill.category
                tagsText = skill.tags.joined(separator: ", ")
            }
        }
    }
}
