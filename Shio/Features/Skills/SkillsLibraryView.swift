import SwiftUI
import SwiftData

/// The universal **Skills** library — Shio's home for vendor-neutral agent
/// rules (à la chops.md): one set of conventions every terminal agent (Claude
/// Code, Codex, Cursor, …) follows, global by default and tweakable per project.
///
/// This is the GLOBAL library (Settings). Global skills (`project == nil`) apply
/// to every project when enabled; the per-project layer lives on the project
/// dashboard. Shared by the iOS and Mac Settings surfaces; CloudKit-synced.
struct SkillsLibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Skill.createdAt, order: .forward) private var allSkills: [Skill]
    @State private var editing: Skill?
    @State private var addingNew = false
    @State private var importNote: String?

    private var globals: [Skill] { allSkills.filter(\.isGlobal) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Skills")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(ShioTheme.textPrimary)
                    Text("Your universal library — applies to every project, tweak per-project.")
                        .font(.system(size: 13))
                        .foregroundStyle(ShioTheme.textTertiary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    ShioSectionHeader("library") {
                        Button { addingNew = true } label: {
                            Text("+ new skill").font(ShioKitFont.rowMeta).foregroundStyle(ShioTheme.accent)
                        }.buttonStyle(.plain)
                    }
                    .padding(.bottom, 6)
                    if globals.isEmpty { emptyState }
                    else { ForEach(globals) { skill in skillRow(skill) } }
                    #if os(macOS)
                    HStack(spacing: 10) {
                        ShioButton("Import from this Mac", .secondary, icon: "square.and.arrow.down", compact: true) {
                            let n = SkillImporter.importLocal(into: context)
                            importNote = n == 0 ? "No new skills found on this Mac." : "Imported \(n) skill\(n == 1 ? "" : "s")."
                            SkillMaterializer.shared.scheduleGlobalSync()
                        }
                        if let importNote {
                            Text(importNote).font(.system(size: 11)).foregroundStyle(ShioTheme.textTertiary)
                        }
                    }
                    .padding(.top, 8).padding(.horizontal, 6)
                    #endif
                }

                VStack(alignment: .leading, spacing: 4) {
                    ShioSectionHeader("vendor sync").padding(.bottom, 4)
                    HStack(spacing: 10) {
                        Text("◑").foregroundStyle(ShioTheme.textTertiary)
                        Text("Claude Code · Codex · Cursor")
                            .font(.system(size: 13)).foregroundStyle(ShioTheme.textPrimary)
                        Spacer()
                        Text("one library, every agent")
                            .font(.system(size: 11)).foregroundStyle(ShioTheme.textTertiary)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 9)
                }
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ShioTheme.background)
        .sheet(isPresented: $addingNew) { SkillEditor(skill: nil, project: nil) }
        .sheet(item: $editing) { skill in SkillEditor(skill: skill, project: nil) }
        #if !os(macOS)
        .navigationTitle("Skills")
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func skillRow(_ skill: Skill) -> some View {
        HStack(spacing: 10) {
            Button { skill.enabled.toggle(); try? context.save(); SkillMaterializer.shared.scheduleGlobalSync() } label: {
                Image(systemName: skill.enabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(skill.enabled ? ShioTheme.success : ShioTheme.textTertiary)
            }.buttonStyle(.plain)
            Button { editing = skill } label: {
                Text(skill.name)
                    .font(.system(size: 13))
                    .foregroundStyle(skill.enabled ? ShioTheme.textPrimary : ShioTheme.textSecondary)
                    .strikethrough(!skill.enabled, color: ShioTheme.textTertiary)
            }.buttonStyle(.plain)
            Spacer()
            ShioChip(text: skill.enabled ? "global" : "off", status: skill.enabled ? .accent : .neutral)
        }
        .padding(.horizontal, 6).padding(.vertical, 9)
        .contextMenu {
            Button("Edit") { editing = skill }
            Button("Remove", role: .destructive) {
                SkillMaterializer.shared.retire(skill, isLocalHost: skillsIsLocalHost)
                context.delete(skill); try? context.save()
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No skills yet.")
                .font(.system(size: 14, weight: .medium)).foregroundStyle(ShioTheme.textPrimary)
            Text("Add a rule every agent follows — \"swift-style\", \"no comments unless asked\", \"commit-haiku\". Global by default; layer project-specific ones on the project dashboard.")
                .font(.system(size: 13)).foregroundStyle(ShioTheme.textSecondary)
            ShioButton("New skill", .primary, icon: "plus") { addingNew = true }.padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: ShioRadius.md, style: .continuous).fill(ShioTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: ShioRadius.md, style: .continuous).strokeBorder(ShioTheme.line, lineWidth: 1))
    }
}

/// Add or edit one skill. `project` nil = a global skill; set = project-scoped.
struct SkillEditor: View {
    let skill: Skill?
    let project: Project?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var desc = ""
    @State private var content = ""
    @State private var nameError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(skill == nil ? "New skill" : "Edit skill")
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(ShioTheme.textPrimary)
            TextField("name (e.g. swift-style)", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 14, design: .monospaced))
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ShioTheme.surface))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(ShioTheme.line, lineWidth: 1))
            if let nameError {
                Text(nameError)
                    .font(.system(size: 12))
                    .foregroundStyle(ShioTheme.danger)
            }
            TextField("description — when should the agent use this?", text: $desc)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ShioTheme.surface))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(ShioTheme.line, lineWidth: 1))
            Text("The rule")
                .font(ShioKitFont.label).tracking(1).textCase(.uppercase)
                .foregroundStyle(ShioTheme.textTertiary)
            TextEditor(text: $content)
                .font(.system(size: 13, design: .monospaced))
                .frame(minHeight: 140)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ShioTheme.surface))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(ShioTheme.line, lineWidth: 1))
            HStack {
                if skill != nil {
                    Button("Delete", role: .destructive) { delete() }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                ShioButton("Save", .primary) { save() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        #if os(macOS)
        .frame(minWidth: 380, idealWidth: 460)
        #endif
        .background(ShioTheme.background)
        .onAppear {
            name = skill?.name ?? ""
            desc = skill?.skillDescription ?? ""
            content = skill?.content ?? ""
        }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        // Two different skills mapping to one dir would clobber and delete
        // each other's SKILL.md on every machine — refuse up front.
        if let dir = Skill.dirName(for: n),
           let clash = (try? context.fetch(FetchDescriptor<Skill>()))?
               .first(where: { $0.persistentModelID != skill?.persistentModelID && $0.dirName == dir }) {
            nameError = "“\(clash.name)” already uses the folder “\(dir)” — pick a more distinct name."
            return
        }
        nameError = nil
        if let skill {
            let oldDir = skill.dirName
            skill.name = n; skill.skillDescription = desc; skill.content = content
            if skill.dirName != oldDir {
                // The rename leaves the old dir behind on every machine —
                // tombstone it so the sweeps catch up, and clear this Mac now.
                SkillMaterializer.addTombstone(oldDir)
                if skill.isGlobal {
                    SkillMaterializer.shared.removeGlobalLocally(dirName: oldDir)
                }
            }
        } else {
            context.insert(Skill(name: n, skillDescription: desc, content: content, project: project))
        }
        try? context.save()
        SkillMaterializer.shared.scheduleGlobalSync()
        // A project-scoped skill lives in its checkouts, not the global store —
        // push the edit (or the rename's sweep) to the active one now.
        if let p = (skill?.project ?? project) {
            SkillMaterializer.shared.materialize(project: p, isLocalHost: skillsIsLocalHost)
        }
        dismiss()
    }

    private func delete() {
        if let skill {
            SkillMaterializer.shared.retire(skill, isLocalHost: skillsIsLocalHost)
            context.delete(skill); try? context.save()
        }
        dismiss()
    }
}

/// The platform's "this is my own machine" test, for the shared skills
/// surfaces (Mac: the self host; iOS: every host is remote).
func skillsIsLocalHost(_ host: Host) -> Bool {
    #if os(macOS)
    MacSelfHost.isThisMac(host)
    #else
    false
    #endif
}
