import SwiftUI
import SwiftData

/// The iPhone frame: Home (this team's conversations), Activity (the
/// cross-project needs-you feed, badged while something's blocked), and More
/// (Machines · Files · Settings) — on the native Liquid Glass dock (his
/// call: the system dock over a custom bar).
struct MainTabsView: View {
    @Query private var projects: [Project]

    private var needsYou: Int {
        ActivityFeed.items(projects: projects).filter { $0.activity == .waiting }.count
    }

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                HomeTabView()
            }
            Tab("Agents", systemImage: "wand.and.sparkles.inverse") {
                ActivityTabView()
            }
            .badge(needsYou)
            Tab("More", systemImage: "ellipsis") {
                MoreTabView()
            }
        }
        .tint(ShioTheme.textPrimary)
    }
}

/// ⋯ More — the quiet utilities: Machines, Files, Settings.
struct MoreTabView: View {
    @Query(sort: \Host.name) private var hosts: [Host]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("More")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(ShioTheme.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)

                NavigationLink { HostListView() } label: {
                    moreRow(systemImage: "desktopcomputer", name: "Machines",
                            meta: hosts.isEmpty ? "" : "\(hosts.dedupedByIdentity.count)")
                }
                .buttonStyle(.plain)
                NavigationLink { FilesView() } label: {
                    moreRow(systemImage: "folder", name: "Files")
                }
                .buttonStyle(.plain)
                NavigationLink { SettingsView() } label: {
                    moreRow(systemImage: "gearshape", name: "Settings")
                }
                .buttonStyle(.plain)

                Spacer()

                Text("塩 shio")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(ShioTheme.textTertiary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
            }
            .background(ShioTheme.background)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func moreRow(systemImage: String, name: String, meta: String = "") -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14))
                .foregroundStyle(ShioTheme.textSecondary)
                .frame(width: 22)
            Text(name)
                .font(.system(size: 15))
                .foregroundStyle(ShioTheme.textPrimary)
            Spacer()
            if !meta.isEmpty {
                Text(meta)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(ShioTheme.textTertiary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ShioTheme.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle().fill(ShioTheme.line).frame(height: 1).padding(.leading, 16)
        }
    }
}
