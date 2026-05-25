import SwiftUI

/// SwiftUI scene that hosts an active session. For now this is shown directly
/// from the root view when a host is picked. Brick 8 (iPad bespoke) will
/// move host-list state into a `NavigationSplitView`.
struct TerminalScene: View {

    @State var viewModel: SessionViewModel

    var body: some View {
        ZStack {
            ShioColor.Terminal.background
                .ignoresSafeArea()

            TerminalView(controller: viewModel.terminal)
                .ignoresSafeArea(.container, edges: .horizontal)

            // Connecting / disconnected overlays — Brick 14 polishes these.
            switch viewModel.state {
            case .connecting:
                ProgressView()
                    .tint(ShioColor.Text.primary)
                    .scaleEffect(1.4)
            case .disconnected(let reason):
                disconnectedOverlay(reason: reason)
            default:
                EmptyView()
            }
        }
        .task {
            await viewModel.start()
        }
        .onDisappear {
            Task { await viewModel.stop() }
        }
    }

    @ViewBuilder
    private func disconnectedOverlay(reason: String?) -> some View {
        VStack(spacing: ShioSpace.md) {
            Text("Disconnected")
                .font(ShioFont.title2)
                .foregroundStyle(ShioColor.Text.primary)
            if let reason {
                Text(reason)
                    .font(ShioFont.callout)
                    .foregroundStyle(ShioColor.Text.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, ShioPadding.screenHorizontalIPhone)
            }
            ShioButton("Reconnect", style: .primary) {
                Task { await viewModel.start() }
            }
            .padding(.horizontal, ShioPadding.screenHorizontalIPhone)
            .padding(.top, ShioSpace.sm)
        }
        .padding(ShioSpace.xl)
        .background(ShioColor.Chrome.surface)
        .clipShape(RoundedRectangle(cornerRadius: ShioRadius.lg, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
        .padding(ShioSpace.xl)
    }
}
