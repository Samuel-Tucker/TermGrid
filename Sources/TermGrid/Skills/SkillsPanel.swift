import SwiftUI

struct SkillsPanel: View {
    var skillsManager: SkillsManager
    let onSendToCompose: (String) -> Bool

    @State private var searchQuery = ""
    @State private var selectedCategory: SkillCategory? = nil
    @State private var expandedSkillIDs: Set<UUID> = []
    @State private var showEditor = false
    @State private var editingSkill: Skill? = nil
    @State private var sendFailMessage = false
    @State private var isScanning = false
    @State private var scanResult: SkillScanner.ScanResult? = nil

    private var filteredSkills: [Skill] {
        skillsManager.filtered(by: selectedCategory, query: searchQuery)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "book")
                    .foregroundColor(Theme.accent)
                Text("Skills")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.headerText)
                Spacer()
                Text("\(skillsManager.skills.count)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.notesSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().foregroundColor(Theme.divider)

            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.notesSecondary)
                TextField("Search skills...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.notesSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            // Category tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    categoryTab(label: "All", category: nil)
                    ForEach(SkillCategory.allCases, id: \.self) { cat in
                        categoryTab(label: cat.displayName, category: cat)
                    }
                }
                .padding(.horizontal, 14)
            }
            .padding(.bottom, 8)

            Divider().foregroundColor(Theme.divider)

            // Send fail message
            if sendFailMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10))
                    Text("Focus a terminal first")
                        .font(.system(size: 11))
                }
                .foregroundColor(Theme.error)
                .padding(.vertical, 6)
                .transition(.opacity)
            }

            // Editor form
            if showEditor {
                SkillEditorForm(
                    existingSkill: editingSkill,
                    onSave: { skill in
                        if editingSkill != nil {
                            skillsManager.updateSkill(skill)
                        } else {
                            skillsManager.addSkill(skill)
                        }
                        showEditor = false
                        editingSkill = nil
                    },
                    onCancel: {
                        showEditor = false
                        editingSkill = nil
                    }
                )
                .padding(.horizontal, 10)
                .padding(.top, 8)
            }

            // Skill list
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filteredSkills) { skill in
                        SkillCard(
                            skill: skill,
                            isExpanded: Binding(
                                get: { expandedSkillIDs.contains(skill.id) },
                                set: { expanded in
                                    if expanded { expandedSkillIDs.insert(skill.id) }
                                    else { expandedSkillIDs.remove(skill.id) }
                                }
                            ),
                            onSend: {
                                let success = onSendToCompose(skill.content)
                                if !success {
                                    withAnimation { sendFailMessage = true }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        withAnimation { sendFailMessage = false }
                                    }
                                }
                            },
                            onEdit: {
                                editingSkill = skill
                                showEditor = true
                            },
                            onDelete: {
                                skillsManager.removeSkill(id: skill.id)
                                expandedSkillIDs.remove(skill.id)
                            }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }

            Spacer(minLength: 0)

            Divider().foregroundColor(Theme.divider)

            // Action buttons
            HStack(spacing: 0) {
                Button {
                    editingSkill = nil
                    showEditor = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("New Skill")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

                Divider().frame(height: 20).foregroundColor(Theme.divider)

                Button {
                    isScanning = true
                    Task {
                        let result = await SkillScanner.scan(existingSkills: skillsManager.skills)
                        isScanning = false
                        scanResult = result
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isScanning {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text("Scan Local")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .disabled(isScanning)
            }
        }
        .frame(width: 320)
        .background(Theme.appBackground)
        .sheet(item: Binding<SkillScanner.ScanResult?>(
            get: { scanResult },
            set: { scanResult = $0 }
        )) { result in
            ScanResultsSheet(
                scanResult: result,
                onImport: { selected in
                    skillsManager.importOrUpdate(selected)
                    scanResult = nil
                },
                onCancel: { scanResult = nil }
            )
        }
    }

    private func categoryTab(label: String, category: SkillCategory?) -> some View {
        Button {
            selectedCategory = category
        } label: {
            Text(label)
                .font(.system(size: 11, weight: selectedCategory == category ? .semibold : .regular))
                .foregroundColor(selectedCategory == category ? Theme.accent : Theme.notesSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(selectedCategory == category ? Theme.cellBackground : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}
