import SwiftUI
import SwiftData

/// The project dashboard on iOS — the home you land on when you open a project
/// (single- or multi-repo). Lists its repos (each opens its own terminal), with
/// rename, add-repo, and a notes scratchpad. Grounding + agent-supervision
/// surfaces land here next.
struct ProjectOverviewView: View {
    @Bindable var project: Project
    let openRepo: (Repo) -> Void
    @Environment(\.modelContext) private var context
    private let status = ProjectStatusStore.shared

    @State private var showingAddRepo = false
    @State private var showingRename = false
    @State private var renameText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ShioSpace.lg) {
                sectionHeader("Repos")
                VStack(spacing: ShioSpace.sm) {
                    ForEach(project.sortedRepos) { repo in
                        repoRow(repo)
                    }
                }

                sectionHeader("Notes")
                TextEditor(text: Binding(
                    get: { project.notes ?? "" },
                    set: { project.notes = $0; try? context.save() }))
                    .font(ShioFont.Mono.inline)
                    .foregroundStyle(ShioColor.Text.primary)
                    .frame(minHeight: 100)
                    .scrollContentBackground(.hidden)
                    .padding(ShioSpace.sm)
                    .background(ShioColor.Chrome.surface)
                    .clipShape(RoundedRectangle(cornerRadius: ShioRadius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: ShioRadius.lg, style: .continuous)
                            .strokeBorder(ShioColor.Chrome.border, lineWidth: 0.5))
            }
            .padding(.horizontal, ShioPadding.screenHorizontalIPhone)
            .padding(.vertical, ShioSpace.md)
        }
        .background(ShioColor.Chrome.background)
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { renameText = project.name; showingRename = true } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button { showingAddRepo = true } label: {
                        Label("Add repo", systemImage: "plus")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(ShioColor.Text.primary)
                }
            }
        }
        .sheet(isPresented: $showingAddRepo) { AddProjectSheet(targetProject: project) }
        .alert("Rename project", isPresented: $showingRename) {
            TextField("Name", text: $renameText)
            Button("Save") {
                let n = renameText.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { project.name = n; try? context.save() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            status.refresh(ProjectStatusStore.targets(for: [project], isLocalHost: { _ in false }))
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(ShioFont.footnote)
            .foregroundStyle(ShioColor.Text.tertiary)
            .tracking(1)
    }

    private func repoRow(_ repo: Repo) -> some View {
        Button { openRepo(repo) } label: {
            HStack(spacing: ShioSpace.md) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(ShioColor.Text.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(repo.name)
                        .font(ShioFont.bodyEmphasis)
                        .foregroundStyle(ShioColor.Text.primary)
                    gitLine(repo)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ShioColor.Text.tertiary)
            }
            .padding(ShioSpace.md)
            .background(ShioColor.Chrome.surface)
            .clipShape(RoundedRectangle(cornerRadius: ShioRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ShioRadius.lg, style: .continuous)
                    .strokeBorder(ShioColor.Chrome.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func gitLine(_ repo: Repo) -> some View {
        let probe = repo.activeCheckout.flatMap { status.status(forHost: $0.host, path: $0.path)?.probe }
        let m = GitLineFormatter.make(probe)
        HStack(spacing: ShioSpace.sm) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 11))
                Text(m.branch).lineLimit(1).truncationMode(.middle)
            }
            .font(ShioFont.Mono.inline)
            .foregroundStyle(ShioColor.Text.secondary)
            if m.hasTracking {
                if m.ahead > 0 { chip("↑\(m.ahead)", ShioColor.Text.secondary) }
                if m.behind > 0 { chip("↓\(m.behind)", ShioColor.Text.secondary) }
                if m.dirty > 0 { chip("●\(m.dirty)", ShioColor.State.warning) }
                else { chip("clean", ShioColor.State.success) }
            }
        }
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text).font(ShioFont.footnote).monospacedDigit().foregroundStyle(color)
    }
}
