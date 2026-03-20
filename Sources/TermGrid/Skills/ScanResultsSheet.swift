import SwiftUI

struct ScanResultsSheet: View {
    let scanResult: SkillScanner.ScanResult
    let onImport: ([Skill]) -> Void
    let onCancel: () -> Void

    @State private var selectedIDs: Set<UUID>
    @State private var expandedCategories: Set<SkillCategory>

    private var importable: [Skill] {
        scanResult.newSkills + scanResult.updatedSkills
    }

    /// Skills grouped by category, sorted: new first, then updated within each group.
    private var grouped: [(category: SkillCategory, skills: [Skill])] {
        let byCategory = Dictionary(grouping: importable) { $0.category }
        let newIDs = Set(scanResult.newSkills.map(\.id))
        return SkillCategory.allCases.compactMap { cat in
            guard let skills = byCategory[cat], !skills.isEmpty else { return nil }
            let sorted = skills.sorted { a, b in
                let aNew = newIDs.contains(a.id)
                let bNew = newIDs.contains(b.id)
                if aNew != bNew { return aNew }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            return (cat, sorted)
        }
    }

    init(scanResult: SkillScanner.ScanResult,
         onImport: @escaping ([Skill]) -> Void,
         onCancel: @escaping () -> Void) {
        self.scanResult = scanResult
        self.onImport = onImport
        self.onCancel = onCancel
        let all = scanResult.newSkills + scanResult.updatedSkills
        _selectedIDs = State(initialValue: Set(all.map(\.id)))
        // Start all populated categories expanded (Kimi: first scan is about discovery)
        let populated = Set(Dictionary(grouping: all) { $0.category }.keys)
        _expandedCategories = State(initialValue: populated)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(Theme.accent)
                Text("Local Skills Found")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.headerText)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            // Summary badges
            HStack(spacing: 8) {
                badge("\(scanResult.newSkills.count) new", color: Theme.staged)
                badge("\(scanResult.updatedSkills.count) updated", color: Theme.accent)
                badge("\(scanResult.skippedCount) unchanged", color: Theme.notesSecondary)
                if !scanResult.errors.isEmpty {
                    badge("\(scanResult.errors.count) errors", color: Theme.error)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            Divider().foregroundColor(Theme.divider)

            if importable.isEmpty {
                Spacer()
                Text("All local skills are already imported.")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.notesSecondary)
                Spacer()
            } else {
                // Grouped skill list
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(grouped, id: \.category) { group in
                            sectionView(category: group.category, skills: group.skills)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }

            Divider().foregroundColor(Theme.divider)

            // Actions
            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.notesSecondary)
                    .font(.system(size: 12, weight: .medium))

                Spacer()

                if !importable.isEmpty {
                    let selected = selectedIDs.count
                    let total = importable.count
                    Button {
                        let skills = importable.filter { selectedIDs.contains($0.id) }
                        onImport(skills)
                    } label: {
                        Text("Import \(selected) of \(total)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(selected > 0 ? Theme.accent : Theme.accentDisabled)
                    }
                    .buttonStyle(.plain)
                    .disabled(selected == 0)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 420, height: 480)
        .background(Theme.appBackground)
    }

    // MARK: - Category Section

    private func sectionView(category: SkillCategory, skills: [Skill]) -> some View {
        let isExpanded = expandedCategories.contains(category)
        let sectionIDs = Set(skills.map(\.id))
        let selectedInSection = selectedIDs.intersection(sectionIDs).count
        let newIDs = Set(scanResult.newSkills.map(\.id))
        let newInSection = skills.filter { newIDs.contains($0.id) }.count
        let updatedInSection = skills.count - newInSection

        return VStack(spacing: 0) {
            // Section header
            HStack(spacing: 6) {
                // Tri-state checkbox
                Button {
                    if selectedInSection == skills.count {
                        // All selected → deselect all
                        selectedIDs.subtract(sectionIDs)
                    } else {
                        // None or partial → select all
                        selectedIDs.formUnion(sectionIDs)
                    }
                } label: {
                    Image(systemName: sectionCheckboxIcon(
                        selected: selectedInSection, total: skills.count))
                        .font(.system(size: 12))
                        .foregroundColor(selectedInSection > 0 ? Theme.accent : Theme.notesSecondary)
                }
                .buttonStyle(.plain)

                // Category color bar
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(categoryColor(category))
                    .frame(width: 3, height: 16)

                Image(systemName: category.icon)
                    .font(.system(size: 10))
                    .foregroundColor(categoryColor(category))

                Text(category.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.headerText)

                Text("\(skills.count)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.notesSecondary)

                // Inline new/updated counts
                if newInSection > 0 {
                    Text("\(newInSection) new")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Theme.staged)
                }
                if updatedInSection > 0 {
                    Text("\(updatedInSection) upd")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Theme.accent)
                }

                Spacer()

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Theme.notesSecondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isExpanded { expandedCategories.remove(category) }
                    else { expandedCategories.insert(category) }
                }
            }

            // Expanded rows
            if isExpanded {
                ForEach(skills) { skill in
                    scanRow(skill)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.cellBackground.opacity(0.5))
        )
    }

    private func sectionCheckboxIcon(selected: Int, total: Int) -> String {
        if selected == 0 { return "square" }
        if selected == total { return "checkmark.square.fill" }
        return "minus.square.fill" // indeterminate
    }

    // MARK: - Skill Row

    private func scanRow(_ skill: Skill) -> some View {
        let isNew = scanResult.newSkills.contains(where: { $0.id == skill.id })
        let isChecked = selectedIDs.contains(skill.id)

        return HStack(spacing: 8) {
            Button {
                if isChecked { selectedIDs.remove(skill.id) }
                else { selectedIDs.insert(skill.id) }
            } label: {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .foregroundColor(isChecked ? Theme.accent : Theme.notesSecondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(skill.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.headerText)
                        .lineLimit(1)

                    originBadge(skill.origin)

                    Text(isNew ? "new" : "update")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(isNew ? Theme.staged : Theme.accent)
                }
                if !skill.description.isEmpty {
                    Text(skill.description)
                        .font(.system(size: 9))
                        .foregroundColor(Theme.notesSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.12))
            )
    }

    private func originBadge(_ origin: SkillOrigin) -> some View {
        let label: String
        let color: Color
        switch origin {
        case .claude: label = "Claude"; color = Theme.agentClaude
        case .codex:  label = "Codex";  color = Theme.agentCodex
        case .manual: label = "Manual"; color = Theme.notesSecondary
        }
        return Text(label)
            .font(.system(size: 8, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(color.opacity(0.5), lineWidth: 0.5)
            )
    }

    private func categoryColor(_ category: SkillCategory) -> Color {
        switch category {
        case .prompt: return Color(hex: "#D4A574")
        case .shell:  return Color(hex: "#75BE95")
        case .code:   return Color(hex: "#A78BFA")
        case .custom: return Color(hex: "#7A756B")
        }
    }
}
