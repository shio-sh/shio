import SwiftUI

/// Agents tab (stub). Phase 4 fills this with a cross-project live list of
/// every running agent and its state, fed by output-watching detection.
struct AgentsView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: ShioSpace.lg) {
                Image(systemName: "sparkles")
                    .font(.largeTitle)
                    .foregroundStyle(ShioColor.Text.secondary)
                Text("Agents")
                    .font(ShioFont.title2)
                    .foregroundStyle(ShioColor.Text.primary)
                Text("Every agent across your projects, at a glance. Coming soon.")
                    .font(ShioFont.body)
                    .foregroundStyle(ShioColor.Text.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ShioColor.Chrome.background)
            .navigationTitle("Agents")
        }
    }
}
