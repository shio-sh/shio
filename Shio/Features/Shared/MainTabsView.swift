import SwiftUI
import SwiftData

/// The iPhone frame: three tabs on a custom mono tab bar — 塩 Home (this
/// team's conversations), ⚑ Activity (the cross-project needs-you feed, with
/// a breathing badge while something's blocked), ⋯ More (Machines · Files ·
/// Settings).
struct MainTabsView: View {
    enum ShioTab { case home, activity, more }
    @State private var tab: ShioTab = .home
    @Query private var projects: [Project]

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case .home:     HomeTabView()
                case .activity: ActivityTabView()
                case .more:     MoreTabView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            ShioTabBar(tab: $tab, needsYou: anyNeedsYou)
        }
        .background(ShioTheme.background)
    }

    private var anyNeedsYou: Bool {
        ActivityFeed.items(projects: projects).contains { $0.activity == .waiting }
    }
}

/// The custom tab bar — rail-tinted, hairline-topped, mono glyph + label.
private struct ShioTabBar: View {
    @Binding var tab: MainTabsView.ShioTab
    let needsYou: Bool

    var body: some View {
        HStack(spacing: 0) {
            item(.home, glyph: "塩", label: "Home")
            item(.activity, glyph: "⚑", label: "Activity", badge: needsYou)
            item(.more, glyph: "⋯", label: "More")
        }
        .frame(height: 56)
        .frame(maxWidth: .infinity)
        .background(ShioTheme.rail.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle().fill(ShioTheme.line).frame(height: 1)
        }
    }

    private func item(_ t: MainTabsView.ShioTab, glyph: String, label: String, badge: Bool = false) -> some View {
        Button {
            Haptics.tap()
            tab = t
        } label: {
            VStack(spacing: 3) {
                Text(glyph)
                    .font(.system(size: 15, design: .monospaced))
                    .overlay(alignment: .topTrailing) {
                        if badge {
                            Text("●")
                                .font(.system(size: 8))
                                .foregroundStyle(ShioTheme.warning)
                                .shioNeedsPulse()
                                .offset(x: 10, y: -3)
                        }
                    }
                Text(label)
                    .font(.system(size: 9.5, design: .monospaced))
            }
            .foregroundStyle(tab == t ? ShioTheme.accent : ShioTheme.textTertiary)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(tab == t ? [.isSelected] : [])
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
                    moreRow(glyph: "⌗", name: "Machines",
                            meta: hosts.isEmpty ? "" : "\(hosts.dedupedByIdentity.count)")
                }
                .buttonStyle(.plain)
                NavigationLink { FilesView() } label: {
                    moreRow(glyph: "▤", name: "Files")
                }
                .buttonStyle(.plain)
                NavigationLink { SettingsView() } label: {
                    moreRow(glyph: "⚙", name: "Settings")
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

    private func moreRow(glyph: String, name: String, meta: String = "") -> some View {
        HStack(spacing: 12) {
            Text(glyph)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(ShioTheme.textTertiary)
                .frame(width: 18)
            Text(name)
                .font(.system(size: 15))
                .foregroundStyle(ShioTheme.textPrimary)
            Spacer()
            if !meta.isEmpty {
                Text(meta)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(ShioTheme.textTertiary)
            }
            Text("›")
                .font(.system(size: 13, design: .monospaced))
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
