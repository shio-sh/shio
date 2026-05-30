import SwiftUI

/// Files tab (stub). Phase 5 fills this with a Finder-style SFTP browser of
/// your machines: navigate, view, and manage files. The one non-terminal tab.
struct FilesView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: ShioSpace.lg) {
                Image(systemName: "folder")
                    .font(.largeTitle)
                    .foregroundStyle(ShioColor.Text.secondary)
                Text("Files")
                    .font(ShioFont.title2)
                    .foregroundStyle(ShioColor.Text.primary)
                Text("Browse and manage files on your machines. Coming soon.")
                    .font(ShioFont.body)
                    .foregroundStyle(ShioColor.Text.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ShioColor.Chrome.background)
            .navigationTitle("Files")
        }
    }
}
