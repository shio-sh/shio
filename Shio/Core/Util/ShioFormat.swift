import Foundation

/// Compact relative age: `now`, `5m`, `2h`, `3d`, `1w`. Empty for nil.
/// Shared across iOS and Mac.
func shioShortAge(_ date: Date?) -> String {
    guard let date else { return "" }
    let s = max(0, Date().timeIntervalSince(date))
    switch s {
    case ..<60:     return "now"
    case ..<3600:   return "\(Int(s / 60))m"
    case ..<86400:  return "\(Int(s / 3600))h"
    case ..<604800: return "\(Int(s / 86400))d"
    default:        return "\(Int(s / 604800))w"
    }
}

/// `/Users/me/Shio` → `~/Shio` for local paths; remote paths pass through.
func shioPrettyPath(_ path: String) -> String {
    (path as NSString).abbreviatingWithTildeInPath
}
