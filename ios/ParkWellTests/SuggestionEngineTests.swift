import XCTest
@testable import ParkWell

final class SuggestionEngineTests: XCTestCase {
    private let engine = SuggestionEngine()

    private func freeStreet(_ name: String, _ meters: Double) -> SuggestionEngine.StreetCandidate {
        .init(name: name, meters: meters, isFree: true, hourlyRateCents: nil)
    }

    private func paidStreet(_ name: String, _ meters: Double,
                            rate: Int?) -> SuggestionEngine.StreetCandidate {
        .init(name: name, meters: meters, isFree: false, hourlyRateCents: rate)
    }

    private func garage(_ name: String, _ meters: Double) -> SuggestionEngine.GarageCandidate {
        .init(name: name, meters: meters)
    }

    // MARK: - Free only

    func testFreeOnlyPicksNearestFreeStreet() {
        let best = engine.best(
            streets: [freeStreet("Maynard St", 400), freeStreet("Agricola St", 150)],
            garages: [], mode: .freeOnly
        )
        XCTAssertEqual(best, .street(name: "Agricola St", meters: 150, isFree: true, hourlyRateCents: nil))
    }

    func testFreeOnlyNeverSuggestsPaidStreetsOrGarages() {
        let best = engine.best(
            streets: [paidStreet("Spring Garden Rd", 100, rate: 325)],
            garages: [garage("Scotia Square Parkade", 50)],
            mode: .freeOnly
        )
        XCTAssertNil(best)
    }

    // MARK: - Cheapest first

    func testCheapestPrefersFreeStreetOverCloserCheapPaid() {
        let best = engine.best(
            streets: [freeStreet("Maynard St", 450), paidStreet("Spring Garden Rd", 100, rate: 150)],
            garages: [], mode: .cheapestFirst
        )
        XCTAssertEqual(best, .street(name: "Maynard St", meters: 450, isFree: true, hourlyRateCents: nil))
    }

    func testCheapestOrdersPaidStreetsByAscendingRate() {
        // The pricier zone is closer — rate wins, not distance.
        let best = engine.best(
            streets: [paidStreet("Barrington St", 100, rate: 475),
                      paidStreet("South Park St", 300, rate: 250)],
            garages: [], mode: .cheapestFirst
        )
        XCTAssertEqual(best, .street(name: "South Park St", meters: 300, isFree: false, hourlyRateCents: 250))
    }

    func testCheapestBreaksRateTiesByDistance() {
        let best = engine.best(
            streets: [paidStreet("Barrington St", 300, rate: 250),
                      paidStreet("South Park St", 100, rate: 250)],
            garages: [], mode: .cheapestFirst
        )
        XCTAssertEqual(best, .street(name: "South Park St", meters: 100, isFree: false, hourlyRateCents: 250))
    }

    func testCheapestRanksUnknownRateAfterKnownRate() {
        // Unknown-but-paid is conservatively assumed pricier, even when closer.
        let best = engine.best(
            streets: [paidStreet("Upper Water St", 80, rate: nil),
                      paidStreet("South Park St", 400, rate: 475)],
            garages: [], mode: .cheapestFirst
        )
        XCTAssertEqual(best, .street(name: "South Park St", meters: 400, isFree: false, hourlyRateCents: 475))
    }

    func testCheapestFallsBackToUnknownRatePaidBeforeGarage() {
        let best = engine.best(
            streets: [paidStreet("Upper Water St", 300, rate: nil)],
            garages: [garage("Scotia Square Parkade", 100)],
            mode: .cheapestFirst
        )
        XCTAssertEqual(best, .street(name: "Upper Water St", meters: 300, isFree: false, hourlyRateCents: nil))
    }

    func testCheapestSuggestsGarageOnlyWhenNoStreets() {
        let best = engine.best(
            streets: [],
            garages: [garage("Scotia Square Parkade", 400), garage("Metropark", 250)],
            mode: .cheapestFirst
        )
        XCTAssertEqual(best, .garage(name: "Metropark", meters: 250))
    }

    // MARK: - Nearest

    func testNearestIsPureDistanceAcrossStreetsAndGarages() {
        let best = engine.best(
            streets: [freeStreet("Maynard St", 400), paidStreet("Spring Garden Rd", 200, rate: 475)],
            garages: [garage("Metropark", 100)],
            mode: .nearest
        )
        XCTAssertEqual(best, .garage(name: "Metropark", meters: 100))
    }

    func testNearestPicksStreetWhenCloserThanGarage() {
        let best = engine.best(
            streets: [paidStreet("Spring Garden Rd", 150, rate: 475)],
            garages: [garage("Metropark", 300)],
            mode: .nearest
        )
        XCTAssertEqual(best, .street(name: "Spring Garden Rd", meters: 150, isFree: false, hourlyRateCents: 475))
    }

    func testNoCandidatesMeansNoSuggestion() {
        XCTAssertNil(engine.best(streets: [], garages: [], mode: .cheapestFirst))
        XCTAssertNil(engine.best(streets: [], garages: [], mode: .nearest))
    }
}
