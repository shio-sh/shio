import SwiftUI
import SwiftData

/// Home tab. Your curated projects (repos on your machines) are the first
/// thing you see when you open Shio. Creation and session wiring land in
/// Phase 2; for now this shows your projects (none yet) and the empty state.
struct ProjectsView: View {

    @Query(sort: \Project.lastOpenedAt, order: .reverse) private var projects: [Project]
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if projects.isEmpty {
                    emptyState
                } else {
                    List(projects) { project in
                        ProjectRow(project: project)
                    }
                    .listStyle(.plain)
                }
            }
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
                        showingSettings = true
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack { SettingsView() }
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
            Text("Connect a machine in Hosts, then add the repos you want to work on here.")
                .font(ShioFont.body)
                .foregroundStyle(ShioColor.Text.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShioColor.Chrome.background)
    }
}

private struct ProjectRow: View {
    let project: Project
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(project.name)
                .font(ShioFont.body)
                .foregroundStyle(ShioColor.Text.primary)
            if let host = project.host {
                Text(host.name)
                    .font(ShioFont.Mono.fingerprint)
                    .foregroundStyle(ShioColor.Text.secondary)
            }
        }
    }
}
