import ActivityKit
import Foundation

/// Attributes for the ParkWell Live Activity (Dynamic Island + Lock Screen).
/// Shared verbatim between the app (which starts/updates the activity) and
/// the widget extension (which renders it).
struct ParkingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var level: StatusLevel
        /// Short label, e.g. "Paid parking".
        var headline: String
        /// One-line detail, e.g. "Barrington St · Zone C · until 6 pm".
        var detail: String
        /// True when the dynamic overlay hasn't refreshed recently — the UI
        /// must show this honestly rather than a confident green/red.
        var isStale: Bool
        var updatedAt: Date
    }

    /// Fixed for the life of one activity.
    var cityName: String
}
