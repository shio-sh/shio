import SwiftUI

/// The universal **Skills** library — Shio's home for vendor-neutral agent
/// rules (à la chops.md): one set of conventions every terminal agent (Claude
/// Code, Codex, Cursor, …) follows, global by default and tweakable per project.
///
/// P2 ships the library *shell* on the terminal-refined kit so the app reads as
/// whole; the editable model + per-project layer + vendor export land in P5
/// (#30). Shared by the iOS and Mac Settings surfaces.
struct SkillsLibraryView: View {
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
                        Text("+ new skill").font(ShioKitFont.rowMeta).foregroundStyle(ShioTheme.textTertiary)
                    }
                    .padding(.bottom, 6)
                    emptyState
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
        #if !os(macOS)
        .navigationTitle("Skills")
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No skills yet.")
                .font(.system(size: 14, weight: .medium)).foregroundStyle(ShioTheme.textPrimary)
            Text("A vendor-neutral skills library — one set of rules every agent follows, global ∪ per-project override — is coming. Each skill is a grounding input your agents pull, the same source the dashboard shows.")
                .font(.system(size: 13)).foregroundStyle(ShioTheme.textSecondary)
            HStack(spacing: 8) {
                ShioChip(text: "global", status: .accent)
                ShioChip(text: "per-project")
                ShioChip(text: "vendor-neutral")
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: ShioRadius.md, style: .continuous).fill(ShioTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: ShioRadius.md, style: .continuous).strokeBorder(ShioTheme.line, lineWidth: 1))
    }
}
