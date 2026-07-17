import CoreLocation
import XCTest
@testable import ParkWell

final class SegmentIndexTests: XCTestCase {
    private func segment(_ name: String, _ coords: [(Double, Double)]) -> StreetSegment {
        StreetSegment(
            id: UUID(), zoneCode: nil, streetName: name, side: "both",
            polyline: coords.map { Coordinate(latitude: $0.0, longitude: $0.1) },
            rules: []
        )
    }

    func testFindsSegmentInSameCell() {
        let barrington = segment("Barrington St", [(44.6476, -63.5728), (44.6488, -63.5722)])
        let index = SegmentIndex(segments: [barrington])
        let hits = index.candidates(near: CLLocationCoordinate2D(latitude: 44.648, longitude: -63.5725))
        XCTAssertEqual(hits.map(\.streetName), ["Barrington St"])
    }

    func testExcludesFarSegment() {
        let downtown = segment("Barrington St", [(44.6476, -63.5728), (44.6488, -63.5722)])
        let bedford = segment("Bedford Hwy", [(44.7280, -63.6650), (44.7300, -63.6640)])
        let index = SegmentIndex(segments: [downtown, bedford])
        let hits = index.candidates(near: CLLocationCoordinate2D(latitude: 44.648, longitude: -63.5725))
        XCTAssertEqual(hits.map(\.streetName), ["Barrington St"])
    }

    func testLongSegmentFoundFromBothEnds() {
        // Spans several cells; must be registered in all of them.
        let long = segment("Bedford Hwy", [(44.6900, -63.6200), (44.7300, -63.6640)])
        let index = SegmentIndex(segments: [long])
        for point in [(44.6905, -63.6205), (44.7295, -63.6635)] {
            let hits = index.candidates(near: CLLocationCoordinate2D(latitude: point.0, longitude: point.1))
            XCTAssertEqual(hits.map(\.streetName), ["Bedford Hwy"], "missed near \(point)")
        }
    }

    func testMultiCellSegmentIsDeduped() {
        let long = segment("Bedford Hwy", [(44.6900, -63.6200), (44.7300, -63.6640)])
        let index = SegmentIndex(segments: [long])
        // A wide lookup that touches many of its cells must return it once.
        let hits = index.candidates(near: CLLocationCoordinate2D(latitude: 44.7100, longitude: -63.6420),
                                    cellRadius: 3)
        XCTAssertEqual(hits.count, 1)
    }

    func testMatchesLinearScanOnFixture() {
        // The index feeds SegmentMatcher; candidates near a point must yield
        // the same nearest segment as scanning everything.
        let segments = [
            segment("A St", [(44.6400, -63.5700), (44.6410, -63.5700)]),
            segment("B St", [(44.6450, -63.5750), (44.6460, -63.5750)]),
            segment("C St", [(44.6500, -63.5800), (44.6510, -63.5800)]),
        ]
        let index = SegmentIndex(segments: segments)
        let matcher = SegmentMatcher()
        let here = CLLocationCoordinate2D(latitude: 44.6455, longitude: -63.5751)

        let viaIndex = matcher.nearestSegment(to: here, in: index.candidates(near: here))
        let viaScan = matcher.nearestSegment(to: here, in: segments)
        XCTAssertEqual(viaIndex?.id, viaScan?.id)
        XCTAssertEqual(viaIndex?.streetName, "B St")
    }
}
