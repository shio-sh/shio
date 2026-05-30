import SwiftUI
import SwiftData

/// Home tab. Your curated projects (repos on your machines). Tap one to open
/// (or resume) its terminal session, opened in the repo under tmux. Add a
/// project by pointing at a repo path on a host you've connected.
struct ProjectsView: View {

    @Query(sort: \Project.lastOpenedAt, order: .reverse) private var projects: [Project]
    @State private var showingSettings = false
    @State private var isAddingProject = false
    @State private var showingTerminal = false
    private let sessionStore = SessionStore.shared

    var body: some View {
        NavigationStack {
            Group {
                if projects.isEmpty {
                    emptyState
                } else {
                    List(projects) { project in
                        Button {
                            if sessionStore.openOrCreate(project: project) != nil {
                                showingTerminal = true
                            }
                        } label: {
                            ProjectRow(project: project)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(ShioColor.Chrome.background)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // TODO(polish): swap for the Departure Mono wordmark.
                    Text("shio")
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundStyle(ShioColor.Text.primary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isAddingProject = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(ShioColor.Text.primary)
                    }
                    .accessibilityLabel("Add project")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .foregroundStyle(ShioColor.Text.primary)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack { SettingsView() }
            }
            .sheet(isPresented: $isAddingProject) {
                AddProjectSheet()
            }
            .fullScreenCover(isPresented: $showingTerminal) {
                TerminalScene()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: ShioSpace.lg) {
            Text("塩")
                .font(ShioFont.kanji(size: 72))
                .foregroundStyle(ShioColor.Text.primary)
            Text("No projects yet")
                .font(ShioFont.title2)
                .foregroundStyle(ShioColor.Text.primary)
            Text("Add a repo from a machine you've connected, and it lives here. Open it to drop straight into a terminal in that folder.")
                .font(ShioFont.callout)
                .foregroundStyle(ShioColor.Text.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            ShioButton("Add a project") {
                isAddingProject = true
            }
            .padding(.horizontal, ShioPadding.screenHorizontalIPhone)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShioColor.Chrome.background)
    }
}

private struct ProjectRow: View {
    let project: Project
    var body: some View {
        HStack(spacing: ShioSpace.md) {
            Image(systemName: "folder.fill")
                .font(.system(size: 18))
                .foregroundStyle(ShioColor.Text.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(ShioFont.bodyEmphasis)
                    .foregroundStyle(ShioColor.Text.primary)
                Text(project.host?.name ?? "No machine")
                    .font(ShioFont.Mono.inline)
                    .foregroundStyle(ShioColor.Text.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ShioColor.Text.tertiary)
        }
        .padding(.vertical, ShioSpace.xs)
    }
}
