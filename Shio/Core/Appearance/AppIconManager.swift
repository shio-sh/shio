import UIKit
import SwiftUI

/// Manages Shio's alternate app icons. The default (primary) is the dark
/// keycap, which lives in `Assets.xcassets/AppIcon.appiconset`. Light
/// keycap is registered as an alternate via `CFBundleIcons` in
/// `Info.plist`. Switching uses the standard UIKit API; iOS shows its
/// own confirmation alert that we can't suppress.
enum AppIconManager {

    /// Each available icon. `rawValue` matches the key under
    /// `CFBundleAlternateIcons` in Info.plist — except `.dark`, which
    /// is the primary icon and uses `nil` when calling `setAlternateIconName`.
    enum Icon: String, CaseIterable, Identifiable {
        case dark   = "AppIconDark"
        case light  = "AppIconLight"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .dark:  return "Dark Keycap"
            case .light: return "Light Keycap"
            }
        }

        /// Preview asset to show in the picker. We bundle the @3x PNGs as
        /// loose resources for iOS's alternate-icon plumbing, and reuse
        /// the same files here so the picker can show what the user will
        /// get on their home screen.
        var previewFileName: String {
            switch self {
            case .dark:  return "AppIconDark60x60@3x"
            case .light: return "AppIconLight60x60@3x"
            }
        }
    }

    @MainActor
    static var current: Icon {
        // iOS reports nil for the primary icon. We treat that as `.dark`.
        guard let name = UIApplication.shared.alternateIconName else { return .dark }
        return Icon(rawValue: name) ?? .dark
    }

    /// Switch the app's home-screen icon. Triggers iOS's native
    /// "You have changed the icon" alert. Completion fires after the
    /// system has applied the change.
    @MainActor
    static func set(_ icon: Icon) async {
        // For the default (dark) icon, iOS expects `nil`. Use the
        // alternate name otherwise.
        let target: String? = (icon == .dark) ? nil : icon.rawValue

        // No-op if we're already on the requested icon.
        if UIApplication.shared.alternateIconName == target { return }
        guard UIApplication.shared.supportsAlternateIcons else { return }

        do {
            try await UIApplication.shared.setAlternateIconName(target)
        } catch {
            // Failures here are typically user-cancel; not surface-worthy.
            print("[shio] setAlternateIconName failed: \(error)")
        }
    }
}
