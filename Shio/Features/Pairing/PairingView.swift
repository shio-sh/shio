import SwiftUI
import SwiftData

/// WhatsApp-Web-style pairing: point the camera at the QR a Shio companion
/// shows, and Shio authorizes this device on that machine and adds it to
/// Hosts. On the simulator (no camera) it falls back to pasting the payload.
struct PairingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    enum Phase: Equatable {
        case scanning
        case manualEntry
        case pairing
        /// Paired. `keyLine` is non-nil only when there was no live companion
        /// endpoint, so the user must paste the key on the machine themselves.
        case paired(name: String, keyLine: String?)
        case failed(String)
    }

    @State private var phase: Phase
    @State private var manualText: String = ""
    @State private var localNetwork = LocalNetworkPrimer()
    /// A payload that arrived as a `shio://pair` deep link (Camera-app scan
    /// or a link tap) — skips the in-app scanner and pairs immediately.
    private let prescanned: String?

    init(prescanned: String? = nil) {
        self.prescanned = prescanned
        _phase = State(initialValue: prescanned != nil ? .pairing
                       : PairingScanner.isSupported ? .scanning : .manualEntry)
    }

    var body: some View {
        NavigationStack {
            content
                .background(ShioTheme.background)
                .navigationTitle("Pair a machine")
                .navigationBarTitleDisplayMode(.inline)
                // Prompt for Local Network access up front — before the camera
                // — so the post-scan POST to the Mac's local endpoint isn't
                // racing the permission and failing on the first try.
                .onAppear {
                    localNetwork.prime()
                    if let prescanned { handle(prescanned) }
                }
                .onDisappear { localNetwork.stop() }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    if PairingScanner.isSupported, phase == .scanning || phase == .manualEntry {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(phase == .manualEntry ? "Scan" : "Paste") {
                                phase = (phase == .manualEntry) ? .scanning : .manualEntry
                            }
                        }
                    }
                }
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .scanning:
            scannerView
        case .manualEntry:
            manualEntryView
        case .pairing:
            statusView(symbol: "key.radiowaves.forward.fill",
                       title: "Pairing…",
                       detail: "Authorizing this device on the machine.",
                       spinner: true)
        case .paired(let name, let keyLine):
            pairedView(name: name, keyLine: keyLine)
        case .failed(let message):
            failedView(message)
        }
    }

    // MARK: - Scanner

    private var scannerView: some View {
        ZStack {
            PairingScanner { value in handle(value) }
                .ignoresSafeArea()
            VStack {
                Spacer()
                Text("Show Shio's QR on your Mac")
                    .font(ShioFont.callout)
                    .foregroundStyle(.white)
                    .padding(.horizontal, ShioSpace.lg)
                    .padding(.vertical, ShioSpace.md)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding(.bottom, ShioSpace.xl)
            }
        }
    }

    // MARK: - Manual entry (simulator / no camera)

    private var manualEntryView: some View {
        VStack(alignment: .leading, spacing: ShioSpace.md) {
            Text("Paste the pairing code")
                .font(ShioFont.title2)
                .foregroundStyle(ShioTheme.textPrimary)
            Text("Run the Shio companion on your machine and paste the pairing payload it prints.")
                .font(ShioFont.callout)
                .foregroundStyle(ShioTheme.textSecondary)
            TextEditor(text: $manualText)
                .font(ShioFont.Mono.inline)
                .foregroundStyle(ShioTheme.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 140)
                .padding(ShioSpace.sm)
                .background(ShioTheme.surface, in: RoundedRectangle(cornerRadius: 10))
            ShioButton("Pair", .primary, fullWidth: true) {
                handle(manualText)
            }
            .disabled(manualText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Spacer()
        }
        .padding(ShioPadding.screenHorizontalIPhone)
    }

    // MARK: - Status screens

    private func statusView(symbol: String, title: String, detail: String, spinner: Bool) -> some View {
        VStack(spacing: ShioSpace.lg) {
            if spinner {
                ProgressView().controlSize(.large)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 44))
                    .foregroundStyle(ShioTheme.textSecondary)
            }
            Text(title)
                .font(ShioFont.title2)
                .foregroundStyle(ShioTheme.textPrimary)
            Text(detail)
                .font(ShioFont.callout)
                .foregroundStyle(ShioTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(ShioPadding.screenHorizontalIPhone)
    }

    private func pairedView(name: String, keyLine: String?) -> some View {
        VStack(spacing: ShioSpace.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(ShioTheme.success)
            Text("Paired with \(name)")
                .font(ShioFont.title2)
                .foregroundStyle(ShioTheme.textPrimary)
                .multilineTextAlignment(.center)
            if let keyLine {
                // No live companion endpoint — the user authorizes manually.
                VStack(alignment: .leading, spacing: ShioSpace.sm) {
                    Text("Add this device's key on the machine to finish:")
                        .font(ShioFont.callout)
                        .foregroundStyle(ShioTheme.textSecondary)
                    Text(keyLine)
                        .font(ShioFont.Mono.fingerprint)
                        .foregroundStyle(ShioTheme.textPrimary)
                        .textSelection(.enabled)
                        .padding(ShioSpace.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ShioTheme.surface, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            ShioButton("Done", .primary, fullWidth: true) { dismiss() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(ShioPadding.screenHorizontalIPhone)
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: ShioSpace.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(ShioTheme.warning)
            Text("Couldn't pair")
                .font(ShioFont.title2)
                .foregroundStyle(ShioTheme.textPrimary)
            Text(message)
                .font(ShioFont.callout)
                .foregroundStyle(ShioTheme.textSecondary)
                .multilineTextAlignment(.center)
            ShioButton("Try again", .primary, fullWidth: true) {
                phase = PairingScanner.isSupported ? .scanning : .manualEntry
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(ShioPadding.screenHorizontalIPhone)
    }

    // MARK: - Pairing flow

    private func handle(_ scanned: String) {
        guard let payload = PairingPayload.parse(scanned) else {
            phase = .failed("That doesn't look like a Shio pairing code. Make sure you're scanning the QR the companion shows.")
            return
        }
        phase = .pairing
        Task { @MainActor in
            do {
                let keyLine = try await PairingService.provisionKey(for: payload)
                let host = upsertHost(from: payload)
                try? context.save()
                Haptics.notifySuccess()
                phase = .paired(name: host.name, keyLine: payload.endpoint == nil ? keyLine : nil)
            } catch {
                Haptics.notifyError()
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Reconcile the scanned machine with what we already have. If a host with
    /// the same `deviceID` exists (the companion's self-Host arrived via iCloud
    /// sync), refresh it in place; otherwise insert a new one. Prevents the
    /// "same Mac shows up twice" duplicate.
    private func upsertHost(from payload: PairingPayload) -> Host {
        if let did = payload.deviceID, !did.isEmpty,
           let existing = try? context.fetch(
                FetchDescriptor<Host>(predicate: #Predicate { $0.deviceID == did })).first {
            existing.name = payload.name
            existing.hostname = payload.host
            existing.port = payload.port
            existing.username = payload.user
            return existing
        }
        let host = PairingService.makeHost(from: payload)
        context.insert(host)
        return host
    }
}
