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
    @State private var showingInspector: Bool = false
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

    /// The active conversation's blocked agent, if any — drives the answer bar.
    private var waitingSnapshot: AgentSnapshot? {
        guard let id = store.activeSession?.id,
              let snap = AgentStateStore.shared.snapshot(for: id),
              snap.activity == .waiting else { return nil }
        return snap
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
        // The agent's question is in the scrollback right above — this is the
        // one-keystroke answer, injected straight into the live channel.
        .overlay(alignment: .bottom) {
            if let viewModel, let waiting = waitingSnapshot {
                NeedBar(agentName: waiting.agentName ?? "Your agent",
                        approve: { Haptics.medium(); viewModel.terminal.onInput?("y\n") },
                        deny: { Haptics.medium(); viewModel.terminal.onInput?("n\n") })
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
        }
        .sheet(isPresented: $showingInspector) {
            if let session = store.activeSession {
                ConversationInspectorSheet(session: session)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
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

    @ViewBuilder
    private var topBar: some View {
        HStack(spacing: ShioSpace.sm) {
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

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(store.activeSession?.displayName ?? "")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(ShioTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

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
        .frame(height: 44)
        .background(.ultraThinMaterial)
    }

    /// The right-side menu button. Lists all live terminals across machines
    /// and offers "New terminal on <current machine>". Tap selects; long
    /// press / swipe-to-delete closes.
    @ViewBuilder
    private var sessionsMenu: some View {
        Menu {
            if !store.sessions.isEmpty {
                Section("Active") {
                    ForEach(store.sessions) { session in
                        Button {
                            Haptics.tap()
                            store.switchTo(session)
                        } label: {
                            Label(
                                session.displayName,
                                systemImage: session.id == store.activeSession?.id ? "checkmark" : "circle"
                            )
                        }
                    }
                }
            }

            if let currentHostID = store.activeSession?.hostID,
               let host = currentHost(id: currentHostID) {
                Section {
                    Button {
                        Haptics.light()
                        store.createNewSession(on: host)
                    } label: {
                        Label("New terminal on \(host.name)", systemImage: "plus")
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
            Image(systemName: store.sessions.count > 1 ? "rectangle.stack.fill" : "ellipsis.circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(ShioTheme.textPrimary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Open terminals")
    }

    private var statusColor: Color {
        guard let vm = viewModel else { return ShioTheme.textTertiary }
        switch vm.state {
        case .connected:    return ShioTheme.success
        case .connecting:   return ShioTheme.warning
        case .reconnecting: return ShioTheme.warning
        case .idle:         return ShioTheme.textTertiary
        case .disconnected: return ShioTheme.danger
        }
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
        }
        .padding(ShioSpace.xl)
        .frame(maxWidth: 480)
        .background(ShioTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: ShioRadius.lg, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
        .padding(ShioSpace.xl)
    }
}

// MARK: - Needs-you answer bar

/// "⚑ Codex is waiting · Approve · Deny" — floats over the terminal while the
/// agent is blocked; the question itself is in the scrollback right above.
private struct NeedBar: View {
    let agentName: String
    let approve: () -> Void
    let deny: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Text("⚑")
                .font(.system(size: 12))
                .foregroundStyle(ShioTheme.warning)
                .shioNeedsPulse()
            Text("\(agentName) is waiting")
                .font(.system(size: 12.5))
                .foregroundStyle(ShioTheme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            ShioMiniButton(title: "Approve", status: .success, action: approve)
            ShioMiniButton(title: "Deny", status: .danger, action: deny)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(ShioTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(ShioTheme.warningBg)
        )
        .overlay(alignment: .leading) {
            Rectangle().fill(ShioTheme.warning).frame(width: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
    }
}

// MARK: - Inspector sheet (▤)

/// The conversation's GLANCE as a sheet: where it runs, who's on it, and the
/// repo's git state. Empty modules disappear (the empty-states law).
private struct ConversationInspectorSheet: View {
    let session: SessionStore.Session
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private var checkout: ProjectCheckout? {
        session.checkoutID.flatMap { context.model(for: $0) as? ProjectCheckout }
    }
    private var snapshot: AgentSnapshot? {
        AgentStateStore.shared.snapshot(for: session.id)
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
                kv("Conversation") { Text(session.displayName).foregroundStyle(ShioTheme.textPrimary) }
                kv("Machine") { Text(session.viewModel.hostName).foregroundStyle(ShioTheme.textPrimary) }
                if let snap = snapshot, snap.activity != .none {
                    kv("Agent") {
                        switch snap.activity {
                        case .waiting:
                            Text("⚑ \(snap.agentName ?? "agent") needs you").foregroundStyle(ShioTheme.warning)
                        case .running:
                            Text("⠿ \(snap.agentName ?? "agent") working").foregroundStyle(ShioTheme.info)
                        default:
                            Text("✓ finished").foregroundStyle(ShioTheme.success)
                        }
                    }
                }
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
