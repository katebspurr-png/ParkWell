import CoreLocation
import Foundation

/// Finds the street segment the driver is currently passing.
struct SegmentMatcher {
    /// GPS in a downtown canyon is easily 10–15 m off; beyond ~30 m we can't
    /// honestly claim to know which block face the driver is beside.
    var maxDistanceMeters: Double = 30

    func nearestSegment(to location: CLLocationCoordinate2D, in segments: [StreetSegment]) -> StreetSegment? {
        var best: (segment: StreetSegment, distance: Double)?
        for segment in segments {
            guard let d = distance(from: location, toPolyline: segment.polyline) else { continue }
            if d <= maxDistanceMeters, d < (best?.distance ?? .infinity) {
                best = (segment, d)
            }
        }
        return best?.segment
    }

    /// Minimum distance in meters from a point to a polyline, using a local
    /// equirectangular projection — accurate to well under a meter at the
    /// scale of a city block.
    func distance(from point: CLLocationCoordinate2D, toPolyline polyline: [Coordinate]) -> Double? {
        guard polyline.count >= 2 else { return nil }
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = 111_320.0 * cos(point.latitude * .pi / 180)

        func project(_ c: Coordinate) -> (x: Double, y: Double) {
            ((c.longitude - point.longitude) * metersPerDegreeLon,
             (c.latitude - point.latitude) * metersPerDegreeLat)
        }

        var minDistance = Double.infinity
        for i in 0..<(polyline.count - 1) {
            let a = project(polyline[i])
            let b = project(polyline[i + 1])
            minDistance = min(minDistance, distanceToSegment(a: a, b: b))
        }
        return minDistance
    }

    /// Distance from the origin to segment a–b in the projected plane.
    private func distanceToSegment(a: (x: Double, y: Double), b: (x: Double, y: Double)) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return (a.x * a.x + a.y * a.y).squareRoot() }
        // Origin is the query point; clamp the projection onto the segment.
        let t = max(0, min(1, (-a.x * dx + -a.y * dy) / lengthSquared))
        let px = a.x + t * dx, py = a.y + t * dy
        return (px * px + py * py).squareRoot()
    }
}
