import Foundation
import SwiftUI

/// `NSUserActivity`-based Handoff between Shio on iPhone and Shio on
/// iPad (and, eventually, Mac Catalyst). When a session is active,
/// Shio publishes an activity describing the host + session index.
/// A nearby device signed into the same iCloud account sees the
/// activity in its Handoff banner / dock and can hand off — opening
/// Shio on that device with the same host pre-selected.
///
/// We're broadcasting only the *connection intent* — not session
/// contents (tmux on the remote handles state). That keeps the
/// payload tiny and avoids any privacy concerns about command history
/// crossing devices.
enum SessionHandoff {

    /// Reverse-DNS activity type. Must match the `NSUserActivityTypes`
    /// entry in Info.plist.
    static let activityType = "sh.shio.app.session"

    /// Build a user activity that advertises the given host. The
    /// receiving device parses the userInfo back into a connect intent.
    static func makeActivity(hostName: String, hostID: String) -> NSUserActivity {
        let activity = NSUserActivity(activityType: activityType)
        activity.title = "Connected to \(hostName)"
        activity.userInfo = [
            "hostID": hostID,
            "hostName": hostName,
        ]
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = false
        activity.isEligibleForPrediction = false
        activity.requiredUserInfoKeys = ["hostID"]
        return activity
    }

    /// Decode a received activity back into the connect parameters.
    /// Returns nil if the activity isn't ours or is missing fields.
    static func decode(_ activity: NSUserActivity) -> (hostID: String, hostName: String)? {
        guard activity.activityType == activityType,
              let userInfo = activity.userInfo,
              let hostID = userInfo["hostID"] as? String,
              let hostName = userInfo["hostName"] as? String
        else { return nil }
        return (hostID, hostName)
    }
}
