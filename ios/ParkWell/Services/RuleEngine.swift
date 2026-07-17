import Foundation

/// The resolved answer for one segment at one moment — everything the Live
/// Activity, audio cue, and main screen need.
struct Verdict: Equatable {
    var level: StatusLevel
    var headline: String
    var detail: String
    /// Phrased for text-to-speech, e.g. "Legal, no time limit."
    var spoken: String
    var isStale: Bool
}

/// Pure, synchronous resolution of segment + overlays + time into a Verdict.
/// No I/O, no clocks — everything injected, so this is fully unit-testable.
struct RuleEngine {
    /// Overlay data older than this is treated as stale. The winter ban can
    /// flip on a few hours' notice, so 6h is the outer bound of trust.
    var overlayStaleThreshold: TimeInterval = 6 * 60 * 60
    var calendar: Calendar

    /// Production uses America/Halifax so rules resolve in the city's local
    /// time regardless of device settings; tests inject their own calendar.
    init(calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Halifax") ?? .current
        return cal
    }()) {
        self.calendar = calendar
    }

    func verdict(segment: StreetSegment?, overlays: DynamicOverlays?, at date: Date) -> Verdict {
        let stale = isStale(overlays: overlays, at: date)

        guard let segment else {
            return Verdict(
                level: .unknown,
                headline: "Unmapped street",
                detail: "No rule data here — check posted signs",
                spoken: "No data for this street. Check the signs.",
                isStale: stale
            )
        }

        // Dynamic overlays override everything static. The declared winter
        // ban only prohibits parking 1–6 a.m. (HRM's posted hours); outside
        // that window it becomes an advisory appended below.
        let banDeclared = overlays?.winterBanActive ?? false
        if banDeclared, (1..<6).contains(calendar.component(.hour, from: date)) {
            return Verdict(
                level: .red,
                headline: "Winter parking ban",
                detail: overlays?.winterBanMessage ?? "Overnight ban in effect 1–6 a.m. — vehicles may be towed",
                spoken: "Winter parking ban in effect. Do not park.",
                isStale: stale
            )
        }
        if let overlays, overlays.streetCleaningActive(for: segment.id, at: date, calendar: calendar) != nil {
            return Verdict(
                level: .red,
                headline: "Street cleaning",
                detail: "\(segment.streetName) · cleaning in progress — no parking",
                spoken: "Street cleaning now. Do not park.",
                isStale: stale
            )
        }

        // Static rules, most restrictive first.
        let active = segment.rules.filter { $0.isActive(at: date, calendar: calendar) }

        if active.contains(where: { $0.kind == .noStopping }) {
            return Verdict(
                level: .red,
                headline: "No stopping",
                detail: "\(segment.streetName) · tow-away zone",
                spoken: "No stopping. Tow zone.",
                isStale: stale
            )
        }
        if active.contains(where: { $0.kind == .accessible }) {
            return Verdict(
                level: .red,
                headline: "Accessible parking only",
                detail: "\(segment.streetName) · permit required",
                spoken: "Accessible permit parking only.",
                isStale: stale
            )
        }
        if active.contains(where: { $0.kind == .permitOnly }) {
            return Verdict(
                level: .red,
                headline: "Permit parking only",
                detail: "\(segment.streetName) · resident permit required",
                spoken: "Permit parking only.",
                isStale: stale
            )
        }
        if let loading = active.first(where: { $0.kind == .loadingZone }) {
            let limit = loading.timeLimitMinutes.map { "\($0) min" } ?? "commercial"
            return banAdvisory(Verdict(
                level: .yellow,
                headline: "Loading zone",
                detail: "\(segment.streetName) · \(limit)",
                spoken: loading.timeLimitMinutes.map { "Loading zone, \($0) minutes." } ?? "Loading zone.",
                isStale: stale
            ), banDeclared: banDeclared)
        }
        if let paid = active.first(where: { $0.kind == .paid }) {
            let until = paid.activeWindowEndMinute(at: date, calendar: calendar).map(clockString) ?? ""
            let zone = segment.zoneCode.map { "Zone \($0)" } ?? "Paid"
            return banAdvisory(Verdict(
                level: .yellow,
                headline: "Paid parking",
                detail: "\(segment.streetName) · \(zone)" + (until.isEmpty ? "" : " · until \(until)"),
                spoken: until.isEmpty ? "Paid parking." : "Paid parking until \(until).",
                isStale: stale
            ), banDeclared: banDeclared)
        }
        if let limited = active.first(where: { $0.kind == .timeLimited }), let limit = limited.timeLimitMinutes {
            return banAdvisory(Verdict(
                level: .yellow,
                headline: "\(limit) min limit",
                detail: "\(segment.streetName) · free, \(limit) minute maximum",
                spoken: "Free parking, \(limit) minute limit.",
                isStale: stale
            ), banDeclared: banDeclared)
        }

        return banAdvisory(
            Verdict(
                level: .green,
                headline: "Free parking",
                detail: "\(segment.streetName) · no restrictions right now",
                spoken: "Legal, no time limit.",
                isStale: stale
            ),
            banDeclared: banDeclared
        )
    }

    /// When a ban is declared but it's not yet 1 a.m., a parkable verdict
    /// still needs to warn the driver they can't stay overnight.
    private func banAdvisory(_ verdict: Verdict, banDeclared: Bool) -> Verdict {
        guard banDeclared, verdict.level == .green || verdict.level == .yellow else { return verdict }
        var updated = verdict
        updated.detail += " · Winter ban tonight 1–6 a.m."
        updated.spoken += " Winter ban tonight, 1 to 6 a.m."
        return updated
    }

    func isStale(overlays: DynamicOverlays?, at date: Date) -> Bool {
        guard let overlays else { return true }
        return date.timeIntervalSince(overlays.fetchedAt) > overlayStaleThreshold
    }

    private func clockString(_ minuteOfDay: Int) -> String {
        let hour24 = minuteOfDay / 60
        let minute = minuteOfDay % 60
        let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
        let suffix = hour24 < 12 ? "a.m." : "p.m."
        return minute == 0 ? "\(hour12) \(suffix)" : String(format: "%d:%02d %@", hour12, minute, suffix)
    }
}
