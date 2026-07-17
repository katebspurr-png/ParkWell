import Foundation

// Shared between the app target and the widget extension. Keep this file
// dependency-free (Foundation only) so the widget stays lightweight.

/// The single glanceable state shown in the Live Activity and spoken aloud.
enum StatusLevel: String, Codable, Hashable {
    /// Legal to park right now.
    case green
    /// Legal with a condition — paid, time-limited, loading zone.
    case yellow
    /// Do not park — no-stopping, permit-only, accessible, winter ban.
    case red
    /// Unmapped segment or data too stale to trust. Never fake confidence.
    case unknown
}

enum RuleKind: String, Codable, Hashable {
    case free
    case paid
    case timeLimited = "time_limited"
    case permitOnly = "permit_only"
    case loadingZone = "loading_zone"
    case noStopping = "no_stopping"
    case accessible
}

/// A recurring weekly window with optional effective dates, so schedule
/// changes (e.g. HRM adding Saturday paid hours on 2026-07-18) can ship in
/// the dataset ahead of time instead of as an app update.
struct TimeWindow: Codable, Hashable {
    /// Calendar convention: 1 = Sunday … 7 = Saturday.
    var weekdays: Set<Int>
    /// Minutes after local midnight, inclusive.
    var startMinute: Int
    /// Minutes after local midnight, exclusive.
    var endMinute: Int
    var effectiveFrom: Date?
    var effectiveUntil: Date?

    func contains(_ date: Date, calendar: Calendar) -> Bool {
        if let from = effectiveFrom, date < from { return false }
        if let until = effectiveUntil, date >= until { return false }
        guard weekdays.contains(calendar.component(.weekday, from: date)) else { return false }
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        return minute >= startMinute && minute < endMinute
    }
}

struct ParkingRule: Codable, Hashable, Identifiable {
    var id: UUID
    var kind: RuleKind
    /// Empty means the rule applies at all times (e.g. a tow zone).
    var windows: [TimeWindow]
    var timeLimitMinutes: Int?
    var note: String?

    func isActive(at date: Date, calendar: Calendar) -> Bool {
        windows.isEmpty || windows.contains { $0.contains(date, calendar: calendar) }
    }

    /// End (in minutes after midnight) of the window active at `date`, for
    /// "paid until 6 pm"-style copy.
    func activeWindowEndMinute(at date: Date, calendar: Calendar) -> Int? {
        windows.first { $0.contains(date, calendar: calendar) }?.endMinute
    }
}

struct Coordinate: Codable, Hashable {
    var latitude: Double
    var longitude: Double
}

/// One side of one block face — the atomic unit of the static layer.
struct StreetSegment: Codable, Hashable, Identifiable {
    var id: UUID
    var zoneCode: String?
    var streetName: String
    /// "north" / "south" / "east" / "west" / "both"
    var side: String
    var polyline: [Coordinate]
    var rules: [ParkingRule]
}

struct StreetCleaningEntry: Codable, Hashable {
    var segmentID: UUID
    /// Calendar convention: 1 = Sunday … 7 = Saturday.
    var weekday: Int
    var startMinute: Int
    var endMinute: Int
}

/// The dynamic overlay layer — changes daily/seasonally, fetched live.
struct DynamicOverlays: Codable, Hashable {
    var winterBanActive: Bool
    var winterBanMessage: String?
    var streetCleaning: [StreetCleaningEntry]
    /// When this snapshot was fetched from the backend, used for staleness.
    var fetchedAt: Date

    func streetCleaningActive(for segmentID: UUID, at date: Date, calendar: Calendar) -> StreetCleaningEntry? {
        let weekday = calendar.component(.weekday, from: date)
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        return streetCleaning.first {
            $0.segmentID == segmentID && $0.weekday == weekday
                && minute >= $0.startMinute && minute < $0.endMinute
        }
    }
}
