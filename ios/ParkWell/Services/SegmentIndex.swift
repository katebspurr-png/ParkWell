import CoreLocation
import Foundation

/// Fixed-grid spatial index over street segments, so each GPS tick scans the
/// handful of segments near the driver instead of all ~18k in HRM.
///
/// Each segment is registered in every grid cell its bounding box touches;
/// lookups gather the cells around the query point. Pure and deterministic —
/// see SegmentIndexTests.
struct SegmentIndex {
    /// 0.005° ≈ 550 m north–south and ≈ 395 m east–west at Halifax's
    /// latitude — comfortably larger than the 30 m match radius at the
    /// default lookup radius of one cell ring.
    private let cellSize: Double
    private var buckets: [Cell: [StreetSegment]] = [:]

    private struct Cell: Hashable {
        var x: Int
        var y: Int
    }

    init(segments: [StreetSegment] = [], cellSize: Double = 0.005) {
        self.cellSize = cellSize
        for segment in segments {
            guard let first = segment.polyline.first else { continue }
            var minLat = first.latitude, maxLat = first.latitude
            var minLon = first.longitude, maxLon = first.longitude
            for coordinate in segment.polyline {
                minLat = min(minLat, coordinate.latitude)
                maxLat = max(maxLat, coordinate.latitude)
                minLon = min(minLon, coordinate.longitude)
                maxLon = max(maxLon, coordinate.longitude)
            }
            for x in index(minLon)...index(maxLon) {
                for y in index(minLat)...index(maxLat) {
                    buckets[Cell(x: x, y: y), default: []].append(segment)
                }
            }
        }
    }

    /// Segments in the (2·cellRadius + 1)² cells around the point, deduped.
    /// cellRadius 1 guarantees ≥ ~395 m of coverage (segment matching);
    /// use 2 for the ~500 m suggestion scan.
    func candidates(near coordinate: CLLocationCoordinate2D, cellRadius: Int = 1) -> [StreetSegment] {
        let cx = index(coordinate.longitude)
        let cy = index(coordinate.latitude)
        var seen = Set<UUID>()
        var result: [StreetSegment] = []
        for dx in -cellRadius...cellRadius {
            for dy in -cellRadius...cellRadius {
                for segment in buckets[Cell(x: cx + dx, y: cy + dy)] ?? []
                where seen.insert(segment.id).inserted {
                    result.append(segment)
                }
            }
        }
        return result
    }

    private func index(_ degrees: Double) -> Int {
        Int((degrees / cellSize).rounded(.down))
    }
}
