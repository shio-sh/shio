import SwiftUI
import SwiftData

/// SwiftUI scene that hosts whichever session in `SessionStore` is
/// currently `activeSession`. Switching sessions, spawning new ones, and
/// closing the active one all flow through the store — TerminalScene
/// just renders whatever's active.
struct TerminalScene: View {

    @State private var showingDiagnose: Bool = false
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
                    .ignoresSafeArea(.container, edges: .horizontal)
                    .id(store.activeSession?.id)  // force rebuild on session swap

                switch viewModel.state {
                case .connecting:
                    ProgressView()
                        .tint(ShioColor.Text.primary)
                        .scaleEffect(1.4)
                case .reconnecting:
                    reconnectingOverlay
                case .disconnected(let reason):
                    disconnectedOverlay(reason: reason)
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
        // Broadcast the current session as a Handoff activity so iPad /
        // Mac Catalyst can pick it up. Republishes whenever the active
        // session changes.
        .userActivity(
            SessionHandoff.activityType,
            isActive: store.activeSession != nil
        ) { activity in
            guard let session = store.activeSession else { return }
            let built = SessionHandoff.makeActivity(
                hostName: session.viewModel.hostName,
                hostID: "\(session.hostID)"
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
                    .foregroundStyle(ShioColor.Text.primary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Close session")

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(store.activeSession?.displayName ?? "")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(ShioColor.Text.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            sessionsMenu
        }
        .padding(.horizontal, ShioSpace.sm)
        .frame(height: 44)
        .background(.ultraThinMaterial)
    }

    /// The right-side menu button. Lists all live sessions across hosts
    /// and offers "New session on <current host>". Tap selects; long
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
                        Label("New session on \(host.name)", systemImage: "plus")
                    }
                }
            }

            if let active = store.activeSession {
                Section {
                    Button(role: .destructive) {
                        Haptics.medium()
                        Task { await store.close(active) }
                    } label: {
                        Label("Close this session", systemImage: "xmark")
                    }
                }
            }
        } label: {
            Image(systemName: store.sessions.count > 1 ? "rectangle.stack.fill" : "ellipsis.circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(ShioColor.Text.primary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Sessions")
    }

    private var statusColor: Color {
        guard let vm = viewModel else { return ShioColor.Text.tertiary }
        switch vm.state {
        case .connected:    return .green
        case .connecting:   return .yellow
        case .reconnecting: return .yellow
        case .idle:         return ShioColor.Text.tertiary
        case .disconnected: return .red
        }
    }

    /// Look up a Host by its SwiftData PersistentIdentifier. Used by the
    /// "New session on <host>" menu item.
    private func currentHost(id: PersistentIdentifier) -> Host? {
        let descriptor = FetchDescriptor<Host>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return all.first { $0.persistentModelID == id }
    }

    // MARK: - Overlays

    @ViewBuilder
    private var reconnectingOverlay: some View {
        HStack(spacing: ShioSpace.xs) {
            ProgressView()
                .controlSize(.small)
                .tint(ShioColor.Text.secondary)
            Text("Reconnecting…")
                .font(ShioFont.footnote)
                .foregroundStyle(ShioColor.Text.secondary)
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
                .foregroundStyle(ShioColor.Text.primary)
            if let reason {
                Text(reason)
                    .font(ShioFont.callout)
                    .foregroundStyle(ShioColor.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: ShioSpace.sm) {
                ShioButton("Reconnect", style: .primary) {
                    Task { await viewModel?.start() }
                }
                ShioButton("Diagnose", style: .secondary) {
                    showingDiagnose = true
                }
            }
            .padding(.top, ShioSpace.sm)
        }
        .padding(ShioSpace.xl)
        .frame(maxWidth: 480)
        .background(ShioColor.Chrome.surface)
        .clipShape(RoundedRectangle(cornerRadius: ShioRadius.lg, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
        .padding(ShioSpace.xl)
    }
}
