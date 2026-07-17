import XCTest
@testable import ParkWell

final class RuleEngineTests: XCTestCase {
    private var engine: RuleEngine!
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Halifax")!
        engine = RuleEngine(calendar: calendar)
    }

    // MARK: - Fixtures

    /// Zone C paid parking: Mon–Fri 8–18 always, Sat 8–18 effective 2026-07-18.
    private func paidSegment() -> StreetSegment {
        let weekdayWindow = TimeWindow(
            weekdays: [2, 3, 4, 5, 6], startMinute: 8 * 60, endMinute: 18 * 60,
            effectiveFrom: nil, effectiveUntil: nil
        )
        let saturdayWindow = TimeWindow(
            weekdays: [7], startMinute: 8 * 60, endMinute: 18 * 60,
            effectiveFrom: date(2026, 7, 18, 0, 0), effectiveUntil: nil
        )
        let rule = ParkingRule(
            id: UUID(), kind: .paid,
            windows: [weekdayWindow, saturdayWindow],
            timeLimitMinutes: nil, note: nil
        )
        return StreetSegment(
            id: UUID(), zoneCode: "C", streetName: "Barrington St", side: "east",
            polyline: [Coordinate(latitude: 44.6476, longitude: -63.5728),
                       Coordinate(latitude: 44.6488, longitude: -63.5722)],
            rules: [rule]
        )
    }

    private func freshOverlays(banActive: Bool = false, at date: Date) -> DynamicOverlays {
        DynamicOverlays(winterBanActive: banActive, winterBanMessage: nil,
                        streetCleaning: [], fetchedAt: date)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day,
                                           hour: hour, minute: minute))!
    }

    // MARK: - Paid parking windows

    func testWeekdayDuringPaidHoursIsYellow() {
        // Wednesday 2026-07-15, 10:00
        let now = date(2026, 7, 15, 10, 0)
        let verdict = engine.verdict(segment: paidSegment(), overlays: freshOverlays(at: now), at: now)
        XCTAssertEqual(verdict.level, .yellow)
        XCTAssertEqual(verdict.headline, "Paid parking")
        XCTAssertTrue(verdict.spoken.contains("6 p.m."))
    }

    func testWeekdayEveningIsGreen() {
        // Wednesday 19:00 — after paid hours
        let now = date(2026, 7, 15, 19, 0)
        let verdict = engine.verdict(segment: paidSegment(), overlays: freshOverlays(at: now), at: now)
        XCTAssertEqual(verdict.level, .green)
    }

    func testSaturdayBeforeScheduleChangeIsGreen() {
        // Saturday 2026-07-11, 10:00 — Saturday paid hours start 2026-07-18
        let now = date(2026, 7, 11, 10, 0)
        let verdict = engine.verdict(segment: paidSegment(), overlays: freshOverlays(at: now), at: now)
        XCTAssertEqual(verdict.level, .green)
    }

    func testSaturdayAfterScheduleChangeIsYellow() {
        // Saturday 2026-07-25, 10:00 — new Saturday paid hours in effect
        let now = date(2026, 7, 25, 10, 0)
        let verdict = engine.verdict(segment: paidSegment(), overlays: freshOverlays(at: now), at: now)
        XCTAssertEqual(verdict.level, .yellow)
    }

    func testSundayIsGreen() {
        let now = date(2026, 7, 19, 12, 0)
        let verdict = engine.verdict(segment: paidSegment(), overlays: freshOverlays(at: now), at: now)
        XCTAssertEqual(verdict.level, .green)
    }

    // MARK: - Dynamic overlays

    func testWinterBanIsRedDuringBanHours() {
        // 2 a.m. — inside HRM's 1–6 a.m. enforcement window
        let now = date(2026, 1, 14, 2, 0)
        let verdict = engine.verdict(segment: paidSegment(),
                                     overlays: freshOverlays(banActive: true, at: now), at: now)
        XCTAssertEqual(verdict.level, .red)
        XCTAssertEqual(verdict.headline, "Winter parking ban")
    }

    func testDeclaredBanOutsideBanHoursIsAdvisoryOnly() {
        // Wednesday 10 a.m. — ban declared for tonight, but parking is legal
        // now (paid hours active), so the verdict stays yellow with a warning.
        let now = date(2026, 1, 14, 10, 0)
        let verdict = engine.verdict(segment: paidSegment(),
                                     overlays: freshOverlays(banActive: true, at: now), at: now)
        XCTAssertEqual(verdict.level, .yellow)
        XCTAssertEqual(verdict.headline, "Paid parking")
        XCTAssertTrue(verdict.detail.contains("Winter ban tonight"))
        XCTAssertTrue(verdict.spoken.contains("Winter ban tonight"))
    }

    func testDeclaredBanEveningGreenGetsAdvisory() {
        // 11 p.m. — free parking now, but the driver must know about 1 a.m.
        let now = date(2026, 1, 14, 23, 0)
        let verdict = engine.verdict(segment: paidSegment(),
                                     overlays: freshOverlays(banActive: true, at: now), at: now)
        XCTAssertEqual(verdict.level, .green)
        XCTAssertTrue(verdict.detail.contains("Winter ban tonight"))
    }

    func testStreetCleaningIsRedDuringWindow() {
        let segment = paidSegment()
        let now = date(2026, 7, 16, 9, 0)  // Thursday 09:00
        let overlays = DynamicOverlays(
            winterBanActive: false, winterBanMessage: nil,
            streetCleaning: [StreetCleaningEntry(segmentID: segment.id, weekday: 5,
                                                 startMinute: 8 * 60, endMinute: 12 * 60)],
            fetchedAt: now
        )
        let verdict = engine.verdict(segment: segment, overlays: overlays, at: now)
        XCTAssertEqual(verdict.level, .red)
        XCTAssertEqual(verdict.headline, "Street cleaning")
    }

    // MARK: - Restrictive static rules

    func testNoStoppingBeatsPaid() {
        var segment = paidSegment()
        segment.rules.append(ParkingRule(id: UUID(), kind: .noStopping, windows: [],
                                         timeLimitMinutes: nil, note: nil))
        let now = date(2026, 7, 15, 10, 0)
        let verdict = engine.verdict(segment: segment, overlays: freshOverlays(at: now), at: now)
        XCTAssertEqual(verdict.level, .red)
        XCTAssertEqual(verdict.headline, "No stopping")
    }

    func testLoadingZoneIsYellowWithLimit() {
        let segment = StreetSegment(
            id: UUID(), zoneCode: nil, streetName: "Argyle St", side: "west",
            polyline: [], rules: [
                ParkingRule(id: UUID(), kind: .loadingZone,
                            windows: [TimeWindow(weekdays: [2, 3, 4, 5, 6],
                                                 startMinute: 7 * 60, endMinute: 18 * 60,
                                                 effectiveFrom: nil, effectiveUntil: nil)],
                            timeLimitMinutes: 15, note: nil),
            ]
        )
        let now = date(2026, 7, 15, 10, 0)
        let verdict = engine.verdict(segment: segment, overlays: freshOverlays(at: now), at: now)
        XCTAssertEqual(verdict.level, .yellow)
        XCTAssertEqual(verdict.spoken, "Loading zone, 15 minutes.")
    }

    // MARK: - Pay stations

    func testPaidVerdictIncludesNearestPayStation() {
        let now = date(2026, 7, 15, 10, 0)
        let station = PayStation(id: UUID(), tid: "PS147", zoneCode: "C",
                                 street: "Spring Garden", latitude: 44.643, longitude: -63.578)
        let verdict = engine.verdict(segment: paidSegment(), overlays: freshOverlays(at: now),
                                     nearestPayStation: station, at: now)
        XCTAssertEqual(verdict.level, .yellow)
        XCTAssertTrue(verdict.detail.contains("Pay station PS147"))
    }

    // MARK: - Honesty about missing/stale data

    func testUnmappedSegmentIsUnknown() {
        let now = date(2026, 7, 15, 10, 0)
        let verdict = engine.verdict(segment: nil, overlays: freshOverlays(at: now), at: now)
        XCTAssertEqual(verdict.level, .unknown)
    }

    func testMissingOverlaysAreStale() {
        let now = date(2026, 7, 15, 10, 0)
        let verdict = engine.verdict(segment: paidSegment(), overlays: nil, at: now)
        XCTAssertTrue(verdict.isStale)
        // Static verdict still computed — stale, not blank.
        XCTAssertEqual(verdict.level, .yellow)
    }

    func testOldOverlaysAreStale() {
        let now = date(2026, 7, 15, 10, 0)
        let old = freshOverlays(at: now.addingTimeInterval(-7 * 60 * 60))
        let verdict = engine.verdict(segment: paidSegment(), overlays: old, at: now)
        XCTAssertTrue(verdict.isStale)
    }

    func testFreshOverlaysAreNotStale() {
        let now = date(2026, 7, 15, 10, 0)
        let verdict = engine.verdict(segment: paidSegment(), overlays: freshOverlays(at: now), at: now)
        XCTAssertFalse(verdict.isStale)
    }
}
