import SwiftUI

/// Settings sub-screen that lets the user choose between the dark and
/// light keycap app icons. Selection triggers iOS's native confirmation
/// alert; we update the visible selection optimistically and revert on
/// failure (which is rare — usually user cancel).
struct IconPickerView: View {
    @State private var selected: AppIconManager.Icon = AppIconManager.current

    var body: some View {
        Form {
            Section {
                ForEach(AppIconManager.Icon.allCases) { icon in
                    Button {
                        choose(icon)
                    } label: {
                        HStack(spacing: ShioSpace.md) {
                            iconPreview(for: icon)
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(
                                    cornerRadius: 60 * 0.2237,
                                    style: .continuous
                                ))
                                .overlay(
                                    RoundedRectangle(
                                        cornerRadius: 60 * 0.2237,
                                        style: .continuous
                                    )
                                    .stroke(ShioTheme.line, lineWidth: 0.5)
                                )
                            VStack(alignment: .leading, spacing: ShioSpace.xxs) {
                                Text(icon.displayName)
                                    .font(ShioFont.body)
                                    .foregroundStyle(ShioTheme.textPrimary)
                                if icon == .dark {
                                    Text("Default")
                                        .font(ShioFont.footnote)
                                        .foregroundStyle(ShioTheme.textTertiary)
                                }
                            }
                            Spacer()
                            if selected == icon {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(ShioTheme.success)
                                    .font(.title3)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("iOS will ask you to confirm the change. The new icon takes effect on your home screen immediately.")
                    .font(ShioFont.footnote)
                    .foregroundStyle(ShioTheme.textTertiary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(ShioTheme.background)
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Re-sync in case the user changed the icon out-of-band
            // (e.g., from the long-press home-screen menu on iOS).
            selected = AppIconManager.current
        }
    }

    @ViewBuilder
    private func iconPreview(for icon: AppIconManager.Icon) -> some View {
        // The bundled @3x PNG drives the preview so the user sees the
        // exact pixels that will land on their home screen. We have to
        // load via UIImage(named:) because the files are bundle resources
        // (not in the asset catalog).
        if let image = UIImage(named: icon.previewFileName) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
        }
    }

    private func choose(_ icon: AppIconManager.Icon) {
        guard icon != selected else { return }
        let previous = selected
        selected = icon  // optimistic
        Task {
            await AppIconManager.set(icon)
            // If iOS rejected the change (user cancel, etc.) the real
            // state will diverge from our optimistic update — re-sync.
            await MainActor.run {
                let actual = AppIconManager.current
                if actual != selected {
                    selected = actual == previous ? previous : actual
                }
            }
        }
    }
}
