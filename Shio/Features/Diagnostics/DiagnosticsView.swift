import SwiftUI
import UIKit

/// Live view onto `TailscaleDiagnostic`. Renders the four checks as a
/// stacked list with status icons, detail copy, and per-row remediation
/// actions. Two entry points:
///
///   - **Settings → Diagnose connection.** No target host; only the three
///     environment-level checks run (`hostReachable` is skipped).
///   - **Disconnect overlay → Diagnose.** Accepts the failed host so
///     `hostReachable` runs against the same target the SSH client just
///     tried.
struct DiagnosticsView: View {

    let targetHost: String?
    let targetPort: Int

    @State private var report: TailscaleDiagnostic.Report = .empty
    @State private var isRunning: Bool = false

    init(targetHost: String? = nil, targetPort: Int = 22) {
        self.targetHost = targetHost
        self.targetPort = targetPort
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ShioSpace.lg) {
                header
                ForEach(TailscaleDiagnostic.Check.allCases, id: \.self) { check in
                    DiagnosticRow(check: check, result: report.results[check])
                }
                if isRunning {
                    HStack(spacing: ShioSpace.sm) {
                        ProgressView().tint(ShioTheme.textSecondary)
                        Text("Checking…")
                            .font(ShioFont.callout)
                            .foregroundStyle(ShioTheme.textSecondary)
                    }
                    .padding(.top, ShioSpace.sm)
                }
            }
            .padding(.horizontal, ShioPadding.screenHorizontalIPhone)
            .padding(.vertical, ShioSpace.xl)
        }
        .background(ShioTheme.background)
        .navigationTitle("Diagnose")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isRunning)
            }
        }
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ShioSpace.sm) {
            Text("What we can check")
                .font(ShioFont.title2)
                .foregroundStyle(ShioTheme.textPrimary)
            Text("Shio can verify some things directly and infer others from how connections fail. Each row tells you what we know and what to do next.")
                .font(ShioFont.callout)
                .foregroundStyle(ShioTheme.textSecondary)
        }
    }

    private func refresh() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        report = await TailscaleDiagnostic.shared.run(
            targetHost: targetHost,
            targetPort: targetPort
        )
    }
}

// MARK: - Row

private struct DiagnosticRow: View {
    let check: TailscaleDiagnostic.Check
    let result: TailscaleDiagnostic.CheckResult?

    @State private var expanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: ShioSpace.sm) {
            HStack(alignment: .firstTextBaseline, spacing: ShioSpace.md) {
                statusIcon
                    .frame(width: 18, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text(check.title)
                        .font(ShioFont.bodyEmphasis)
                        .foregroundStyle(ShioTheme.textPrimary)
                    if let reason = statusReason {
                        Text(reason)
                            .font(ShioFont.callout)
                            .foregroundStyle(secondaryColor)
                    }
                }
                Spacer()
                if hasDetail {
                    Button {
                        withAnimation(ShioMotion.standard) { expanded.toggle() }
                    } label: {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ShioTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            if expanded, hasDetail {
                expandedBlock
            }
        }
        .padding(ShioSpace.md)
        .background(ShioTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: ShioRadius.md, style: .continuous))
    }

    private var statusIcon: some View {
        Group {
            switch result?.status {
            case .passed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(ShioTheme.success)
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(ShioTheme.danger)
            case .skipped:
                Image(systemName: "minus.circle")
                    .foregroundStyle(ShioTheme.textTertiary)
            case .running, .idle, .none:
                Image(systemName: "circle.dotted")
                    .foregroundStyle(ShioTheme.textTertiary)
            }
        }
    }

    private var statusReason: String? {
        switch result?.status {
        case .passed:                 return nil
        case .failed(let reason):     return reason
        case .skipped(let reason):    return reason
        case .running:                return "Checking…"
        case .idle, .none:            return "Not checked yet"
        }
    }

    private var secondaryColor: Color {
        switch result?.status {
        case .failed:  return ShioTheme.textPrimary
        case .skipped: return ShioTheme.textTertiary
        default:       return ShioTheme.textSecondary
        }
    }

    private var hasDetail: Bool {
        if let detail = result?.detail, !detail.isEmpty { return true }
        if let r = result?.remediation, r != .none { return true }
        return false
    }

    @ViewBuilder
    private var expandedBlock: some View {
        VStack(alignment: .leading, spacing: ShioSpace.sm) {
            if let detail = result?.detail, !detail.isEmpty {
                Text(detail)
                    .font(ShioFont.callout)
                    .foregroundStyle(ShioTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let remediation = result?.remediation, remediation != .none {
                remediationButton(remediation)
            }
        }
        .padding(.leading, ShioSpace.xl)
        .padding(.top, ShioSpace.xs)
    }

    @ViewBuilder
    private func remediationButton(_ remediation: TailscaleDiagnostic.Remediation) -> some View {
        switch remediation {
        case .openTailscaleApp:
            LegacyButton("Open Tailscale", style: .secondary) {
                TailscaleDetector.openTailscaleOrAppStore()
            }
        case .openTailscaleAppStorePage:
            LegacyButton("Get Tailscale", style: .secondary) {
                TailscaleDetector.openTailscaleOrAppStore()
            }
        case .openMacSharingSettings(let text):
            Text(text)
                .font(ShioFont.Mono.fingerprint)
                .foregroundStyle(ShioTheme.textPrimary)
                .padding(ShioSpace.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ShioTheme.background)
                .clipShape(RoundedRectangle(cornerRadius: ShioRadius.sm, style: .continuous))
        case .useIPInstead:
            Text("Open https://login.tailscale.com/admin/machines on any device to find your Mac's 100.x.y.z IP, then add it as a machine in Shio.")
                .font(ShioFont.footnote)
                .foregroundStyle(ShioTheme.textTertiary)
        case .none:
            EmptyView()
        }
    }
}
