import SwiftUI
import SwiftData

/// SwiftUI scene that hosts whichever session in `SessionStore` is
/// currently `activeSession`. Switching sessions, spawning new ones, and
/// closing the active one all flow through the store — TerminalScene
/// just renders whatever's active.
/// Wraps a URL so it can drive a `.sheet(item:)`.
private struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

struct TerminalScene: View {

    @State private var showingDiagnose: Bool = false
    @State private var showingKeyReview: Bool = false
    @State private var showingInspector: Bool = false
    /// The map (tap the title): the rail's grammar as a sheet.
    @State private var showingMap: Bool = false
    @State private var presentedLink: IdentifiableURL?
    /// Live SSH forward backing a loopback OAuth redirect, torn down when the
    /// in-app browser closes.
    @State private var oauthForward: SSHPortForward?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// SessionStore is a singleton; bound here so view updates fire on
    /// activeSession changes.
    @Bindable private var store = SessionStore.shared

    /// Convenience accessor — returns the active SessionViewModel, or
    /// nil if the store has no session (e.g. last one was closed).
    private var viewModel: SessionViewModel? {
        store.activeSession?.viewModel
    }

    var body: some View {
        ZStack {
            Color(hex: LibGhosttyBridge.terminalBackgroundHex)
                .ignoresSafeArea()  // bleed under status bar + home indicator

            if let viewModel {
                TerminalView(controller: viewModel.terminal)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Surface stays inside the safe area so text isn't hidden
                    // under the notch / Dynamic Island in landscape; the black
                    // background above bleeds edge-to-edge.
                    .id(store.activeSession?.id)  // force rebuild on session swap

                switch viewModel.state {
                case .connecting:
                    ProgressView()
                        .tint(ShioTheme.textPrimary)
                        .scaleEffect(1.4)
                case .reconnecting:
                    reconnectingOverlay
                case .disconnected(let reason):
                    disconnectedOverlay(reason: reason)
                case .connected:
                    ZStack {
                        scrollButtons(for: viewModel)
                        if let url = viewModel.detectedURL {
                            linkBanner(url: url, viewModel: viewModel)
                        }
                    }
                default:
                    EmptyView()
                }
            } else {
                // No active session — should be transient; the parent
                // dismisses TerminalScene when this happens.
                EmptyView()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            topBar
        }
        .sheet(isPresented: $showingInspector) {
            if let session = store.activeSession {
                TerminalGlanceSheet(session: session)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
        // The map — the same grammar as every rail: REPOS / SHELLS for the
        // current project. Tapping a row switches this terminal in place;
        // the fullscreen never tears down.
        .sheet(isPresented: $showingMap) {
            PlaceMapSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onAppear { store.isTerminalPresented = true }
        .onDisappear { store.isTerminalPresented = false }
        // Broadcast the current session as a Handoff activity so iPad /
        // Mac Catalyst can pick it up. Republishes whenever the active
        // session changes.
        .userActivity(
            SessionHandoff.activityType,
            isActive: store.activeSession != nil
        ) { activity in
            guard let session = store.activeSession else { return }
            // The activity crosses devices, where persistentModelID strings
            // mean nothing — hand off the synced device id (or the hostname),
            // which the receiving ConnectRouter resolves.
            let host = modelContext.model(for: session.hostID) as? Host
            let built = SessionHandoff.makeActivity(
                hostName: session.viewModel.hostName,
                hostID: host?.deviceID ?? host?.hostname ?? "\(session.hostID)"
            )
            activity.userInfo = built.userInfo
            activity.title = built.title
            activity.requiredUserInfoKeys = built.requiredUserInfoKeys
            activity.isEligibleForHandoff = true
        }
        .task(id: store.activeSession?.id) {
            // Drive the lifecycle from the store: whenever the active
            // session changes, fire its `start()` if it hasn't already
            // been started.
            guard let active = store.activeSession else { return }
            if case .idle = active.viewModel.state {
                await active.viewModel.start()
            }
        }
        .sheet(item: $presentedLink, onDismiss: {
            // Close the loopback forward once the OAuth dance is done.
            let forward = oauthForward
            oauthForward = nil
            Task { await forward?.close() }
        }) { link in
            SafariView(url: link.url)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showingDiagnose) {
            if let viewModel {
                NavigationStack {
                    DiagnosticsView(
                        targetHost: viewModel.hostName,
                        targetPort: viewModel.targetPort
                    )
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { showingDiagnose = false }
                        }
                    }
                }
            }
        }
        .onChange(of: store.activeSession?.id) { _, newID in
            // If the store emptied (last session closed), back out of
            // TerminalScene entirely.
            if newID == nil { dismiss() }
        }
    }

    // MARK: - Top chrome

    /// The terminal's header — the Mac chead on a phone: presence
    /// glyph (⚑/⠋/⎇/%) + repo name + "agent · tmux · machine" + ▤.
    @ViewBuilder
    private var topBar: some View {
        HStack(spacing: 9) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ShioTheme.textPrimary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Close terminal")

            presenceGlyph

            // The title is the way to the map — tap the name, get the rail's
            // grammar as a sheet.
            Button { Haptics.tap(); showingMap = true } label: {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(store.activeSession?.displayName ?? "")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(ShioTheme.textPrimary)
                            .lineLimit(1).truncationMode(.middle)
                        if let sub = terminalSub {
                            Text(sub)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(ShioTheme.textTertiary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ShioTheme.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open the map")

            Spacer(minLength: 0)

            Button { showingInspector = true } label: {
                Image(systemName: "sidebar.trailing")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ShioTheme.textSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Inspector")

            sessionsMenu
        }
        .padding(.horizontal, ShioSpace.sm)
        .frame(height: 48)
        // Flat dark to match the Mac chead — no translucent material lightening
        // the top edge. Hairline separates it from the terminal, like the Mac.
        .background(ShioTheme.background)
        .overlay(alignment: .bottom) { Rectangle().fill(ShioTheme.line).frame(height: 1) }
    }

    /// Presence on this terminal — ⎇ repo at rest, or % for a loose shell.
    /// Mirrors the Mac terminal header.
    private var presenceGlyph: some View {
        Text(store.activeSession?.projectID == nil ? "%" : "⎇")
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(ShioTheme.textTertiary)
    }

    /// "tmux · this mac" — the standing transport, the machine.
    private var terminalSub: String? {
        guard let session = store.activeSession else { return nil }
        return "tmux · \(session.viewModel.hostName)"
    }

    /// The ⋯ menu. Switching lives in the map (tap the title) — this keeps
    /// only the escape hatch ("New shell here") and leaving.
    @ViewBuilder
    private var sessionsMenu: some View {
        Menu {
            if let currentHostID = store.activeSession?.hostID,
               let host = currentHost(id: currentHostID) {
                Section {
                    Button {
                        Haptics.light()
                        store.createNewSession(on: host)
                    } label: {
                        Label("New shell on \(host.name)", systemImage: "plus")
                    }
                }
            }

            if let active = store.activeSession {
                Section {
                    Button(role: .destructive) {
                        Haptics.medium()
                        Task { await store.close(active) }
                    } label: {
                        Label("Close this terminal", systemImage: "xmark")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(ShioTheme.textPrimary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More")
    }

    /// Look up a Host by its SwiftData PersistentIdentifier. Used by the
    /// "New terminal on <machine>" menu item.
    private func currentHost(id: PersistentIdentifier) -> Host? {
        let descriptor = FetchDescriptor<Host>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return all.first { $0.persistentModelID == id }
    }

    // MARK: - Overlays

    /// Bottom banner offering to open a URL printed in the output (an OAuth
    /// link from `claude` / `gh auth`, etc.) in an in-app browser — so a login
    /// triggered from your phone doesn't strand you waiting on a browser popup
    /// on the remote machine.
    @ViewBuilder
    private func linkBanner(url: URL, viewModel: SessionViewModel) -> some View {
        HStack(spacing: ShioSpace.sm) {
            Image(systemName: "link")
                .font(.system(size: 13, weight: .semibold))
            Text("Open \(url.host ?? "link")")
                .font(.system(.footnote, design: .monospaced).weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Button {
                viewModel.clearDetectedURL()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(ShioTheme.textTertiary)
                    .padding(.leading, 2)
            }
            .accessibilityLabel("Dismiss link")
        }
        .foregroundStyle(ShioTheme.textPrimary)
        .padding(.horizontal, ShioSpace.md)
        .padding(.vertical, ShioSpace.sm)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(ShioTheme.textTertiary.opacity(0.25)))
        .contentShape(Capsule())
        .onTapGesture {
            Haptics.tap()
            viewModel.clearDetectedURL()
            Task {
                // If the link redirects to the host's loopback (an OAuth
                // callback), stand up the SSH forward first so the browser's
                // redirect can reach the host, then open the browser.
                oauthForward = await viewModel.prepareLoopbackForward(for: url)
                presentedLink = IdentifiableURL(url: url)
            }
        }
        .padding(.bottom, ShioSpace.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    /// Floating Page Up / Page Down controls, top-right of the terminal.
    /// They page libghostty's scrollback (or, in a full-screen TUI, send a
    /// page-sized wheel scroll) — distinct from the keyboard-accessory
    /// arrows, which send cursor keys to the program.
    @ViewBuilder
    private func scrollButtons(for viewModel: SessionViewModel) -> some View {
        VStack(spacing: 1) {
            scrollButton(symbol: "chevron.up", accessibility: "Page up") {
                viewModel.terminal.pageUp()
            }
            scrollButton(symbol: "chevron.down", accessibility: "Page down") {
                viewModel.terminal.pageDown()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.top, ShioSpace.sm)
        .padding(.trailing, ShioSpace.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    private func scrollButton(symbol: String, accessibility: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ShioTheme.textSecondary)
                .frame(width: 40, height: 36)
                .background(.ultraThinMaterial)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(accessibility)
    }

    @ViewBuilder
    private var reconnectingOverlay: some View {
        HStack(spacing: ShioSpace.xs) {
            ProgressView()
                .controlSize(.small)
                .tint(ShioTheme.textSecondary)
            Text("Reconnecting…")
                .font(ShioFont.footnote)
                .foregroundStyle(ShioTheme.textSecondary)
        }
        .padding(.horizontal, ShioSpace.md)
        .padding(.vertical, ShioSpace.sm)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, ShioSpace.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    @ViewBuilder
    private func disconnectedOverlay(reason: String?) -> some View {
        VStack(alignment: .leading, spacing: ShioSpace.md) {
            Text("Disconnected")
                .font(ShioFont.title2)
                .foregroundStyle(ShioTheme.textPrimary)
            if let reason {
                Text(reason)
                    .font(ShioFont.callout)
                    .foregroundStyle(ShioTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: ShioSpace.sm) {
                ShioButton("Reconnect", .primary, fullWidth: true) {
                    Task { await viewModel?.start() }
                }
                ShioButton("Diagnose", .secondary, fullWidth: true) {
                    showingDiagnose = true
                }
            }
            .padding(.top, ShioSpace.sm)
            if viewModel?.hostKeyConflict == true {
                ShioButton("Review key change", .secondary, fullWidth: true) {
                    showingKeyReview = true
                }
            }
        }
        .padding(ShioSpace.xl)
        .frame(maxWidth: 480)
        .background(ShioTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: ShioRadius.lg, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
        .padding(ShioSpace.xl)
        .confirmationDialog("This server's key changed",
                            isPresented: $showingKeyReview, titleVisibility: .visible) {
            Button("Trust new key & reconnect", role: .destructive) {
                viewModel?.trustNewHostKeyAndReconnect()
            }
            Button("Keep refusing", role: .cancel) {}
        } message: {
            Text(keyReviewMessage)
        }
    }

    /// Show *what* changed, then the decision the user is actually making.
    private var keyReviewMessage: String {
        let base = "If this machine was reinstalled or upgraded, trusting the new key is safe. If you didn't expect a change, keep refusing — the connection could be intercepted."
        guard let m = viewModel?.hostKeyMismatch else { return base }
        let offered = m.offered.map(ShioKnownHosts.shortFingerprint) ?? "unreadable"
        return "Pinned \(ShioKnownHosts.shortFingerprint(m.pinned)) → offered \(offered). " + base
    }
}

// MARK: - The map (tap the title)

/// The rail's grammar as a sheet under the fullscreen terminal: REPOS /
/// SHELLS for the scoped project, plus the project switcher. Tapping a row
/// switches the terminal to that place in place — the fullscreen never
/// tears down.
private struct PlaceMapSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Project.lastOpenedAt, order: .reverse) private var projects: [Project]
    /// A switcher pick; nil scopes to the active place's project.
    @State private var scopedID: PersistentIdentifier?
    @Bindable private var store = SessionStore.shared
    private let status = ProjectStatusStore.shared

    private var project: Project? {
        if let scopedID, let p = context.model(for: scopedID) as? Project { return p }
        if let pid = store.activeSession?.projectID,
           let p = context.model(for: pid) as? Project { return p }
        return projects.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                switcher
                if let project {
                    if !project.sortedRepos.isEmpty {
                        header("repos")
                        ForEach(project.sortedRepos) { repoRow($0) }
                    }
                    let machines = project.allCheckouts.compactMap(\.host).dedupedByIdentity
                    if !machines.isEmpty {
                        header("shells")
                        ForEach(machines) { shellRow($0) }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
        .background(ShioTheme.surface)
    }

    // MARK: switcher

    private var switcher: some View {
        Menu {
            ForEach(projects) { p in
                Button { scopedID = p.persistentModelID } label: {
                    if p.persistentModelID == project?.persistentModelID {
                        Label(p.name, systemImage: "checkmark")
                    } else {
                        Text(p.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 9) {
                if let project { ProjectAvatar(project, size: 22) }
                Text(project?.name ?? "No project")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ShioTheme.textPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ShioTheme.textSecondary)
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Switch project")
    }

    // MARK: rows

    private func repoRow(_ repo: Repo) -> some View {
        row(title: repo.name,
            selected: isOpen(repoNamed: repo.name),
            action: { open(repo) }) {
            Text("⎇").font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(ShioTheme.textTertiary)
        } trailing: {
            let m = GitLineFormatter.make(repo.activeCheckout.flatMap {
                status.status(forHost: $0.host, path: $0.path)?.probe
            })
            if m.dirty > 0 {
                ShioGitStatusLine(model: m, compact: true, size: 11)
            }
        }
    }

    private func shellRow(_ host: Host) -> some View {
        row(title: host.name,
            selected: isOpenShell(host),
            action: { open(host) }) {
            Text("%")
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(ShioTheme.textTertiary)
        } trailing: { EmptyView() }
    }

    private func row<Icon: View, Trailing: View>(
        title: String, selected: Bool, action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon, @ViewBuilder trailing: () -> Trailing) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                icon().frame(width: 15)
                Text(title)
                    .font(.system(size: 13.5, design: .monospaced))
                    .foregroundStyle(selected ? ShioTheme.accent : ShioTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                trailing()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? ShioTheme.accentBg : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func header(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .tracking(2)
            .foregroundStyle(ShioTheme.textTertiary)
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    // MARK: selection + actions

    private func isOpen(repoNamed name: String) -> Bool {
        guard let active = store.activeSession else { return false }
        return active.projectID != nil && active.displayName == name
    }

    private func isOpenShell(_ host: Host) -> Bool {
        guard let active = store.activeSession else { return false }
        return active.projectID == nil && active.hostID == host.persistentModelID
    }

    private func open(_ repo: Repo) {
        guard store.openOrCreate(repo: repo) != nil else { return }
        Haptics.tap()
        dismiss()
    }

    private func open(_ host: Host) {
        store.openOrCreate(host: host)
        Haptics.tap()
        dismiss()
    }
}

// MARK: - Inspector sheet (▤)

/// The terminal's GLANCE as a sheet: where it runs, who's on it, and the
/// repo's git state. Empty modules disappear (the empty-states law).
private struct TerminalGlanceSheet: View {
    let session: SessionStore.Session
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private var checkout: ProjectCheckout? {
        session.checkoutID.flatMap { context.model(for: $0) as? ProjectCheckout }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("GLANCE")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(ShioTheme.textTertiary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ShioTheme.textTertiary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            VStack(alignment: .leading, spacing: 0) {
                kv("Repo") { Text(session.displayName).foregroundStyle(ShioTheme.textPrimary) }
                kv("Machine") { Text(session.viewModel.hostName).foregroundStyle(ShioTheme.textPrimary) }
                if let checkout {
                    let m = GitLineFormatter.make(
                        ProjectStatusStore.shared.status(forHost: checkout.host, path: checkout.path)?.probe)
                    if m.hasTracking {
                        kv("⎇ Branch") { Text(m.branch).foregroundStyle(ShioTheme.textPrimary) }
                        kv("Dirty") {
                            if m.dirty > 0 {
                                Text("\(m.dirty) file\(m.dirty == 1 ? "" : "s")").foregroundStyle(ShioTheme.warning)
                            } else {
                                Text("clean").foregroundStyle(ShioTheme.success)
                            }
                        }
                    }
                    kv("Path") {
                        Text(checkout.path)
                            .foregroundStyle(ShioTheme.textSecondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
            }
            .padding(.horizontal, 16)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ShioTheme.background)
    }

    private func kv<V: View>(_ key: String, @ViewBuilder value: () -> V) -> some View {
        HStack(spacing: 8) {
            Text(key).foregroundStyle(ShioTheme.textSecondary)
            Spacer(minLength: 8)
            value()
        }
        .font(.system(size: 12.5, design: .monospaced))
        .monospacedDigit()
        .padding(.vertical, 7)
    }
}
