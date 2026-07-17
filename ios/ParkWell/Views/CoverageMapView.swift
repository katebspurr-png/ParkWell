import MapKit
import SwiftUI

/// Coverage map: every mapped segment drawn in its *current* status color,
/// pay stations as purple dots, and the user's position. Answers "why does
/// the app say unmapped here?" at a glance — if there's no line near your
/// dot, there's no data there yet.
struct CoverageMapView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var levels: [UUID: StatusLevel] = [:]
    private let engine = RuleEngine()

    var body: some View {
        NavigationStack {
            CoverageMapRepresentable(segments: model.segments,
                                     levels: levels,
                                     payStations: model.payStations)
                .overlay(alignment: .bottom) {
                    legend
                }
                .navigationTitle("Coverage")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    Button("Done") { dismiss() }
                }
                .task(id: model.segments.count) {
                    recomputeLevels()
                }
        }
    }

    /// Status is time-dependent (paid hours, ban windows), so compute each
    /// segment's level once per appearance rather than per frame.
    private func recomputeLevels() {
        let now = Date()
        var computed: [UUID: StatusLevel] = [:]
        for segment in model.segments {
            computed[segment.id] = engine.verdict(segment: segment, overlays: model.overlays, at: now).level
        }
        levels = computed
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendDot(.green, "Park")
            legendDot(.green.opacity(0.45), "Likely OK")
            legendDot(.yellow, "Paid/limited")
            legendDot(.red, "No")
            legendDot(.purple, "Pay station")
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .padding(.bottom, 12)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }
}

/// SwiftUI's `Map` silently stops rendering once its content builder holds a
/// few thousand items — at citywide scale (~7k segments) the map comes up
/// blank. `MKMapView` + `MKMultiPolyline` batches all segments of one status
/// into a single overlay, so the whole city is five overlays instead of 7k.
private struct CoverageMapRepresentable: UIViewRepresentable {
    var segments: [StreetSegment]
    var levels: [UUID: StatusLevel]
    var payStations: [PayStation]

    /// Downtown Halifax, for when there's no location fix yet.
    private static let fallbackRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 44.6488, longitude: -63.5752),
        span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)
    )

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.region = Self.fallbackRegion
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        // Overlays only change when data loads or levels are recomputed.
        let signature = segments.count &* 31 &+ levels.count &* 7 &+ payStations.count
        guard context.coordinator.signature != signature else { return }
        context.coordinator.signature = signature

        map.removeOverlays(map.overlays)

        var grouped: [StatusLevel: [MKPolyline]] = [:]
        for segment in segments {
            var coords = segment.polyline.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
            guard coords.count >= 2 else { continue }
            let polyline = MKPolyline(coordinates: &coords, count: coords.count)
            grouped[levels[segment.id] ?? .unknown, default: []].append(polyline)
        }
        for (level, lines) in grouped {
            let multi = LevelMultiPolyline(lines)
            multi.level = level
            map.addOverlay(multi, level: .aboveRoads)
        }

        for station in payStations {
            let circle = MKCircle(center: CLLocationCoordinate2D(latitude: station.latitude,
                                                                 longitude: station.longitude),
                                  radius: 6)
            map.addOverlay(circle, level: .aboveRoads)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var signature = -1

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let multi = overlay as? LevelMultiPolyline {
                let renderer = MKMultiPolylineRenderer(multiPolyline: multi)
                renderer.strokeColor = multi.level.mapColor
                renderer.lineWidth = 4
                return renderer
            }
            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                renderer.fillColor = .systemPurple
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

private final class LevelMultiPolyline: MKMultiPolyline {
    var level: StatusLevel = .unknown
}

private extension StatusLevel {
    var mapColor: UIColor {
        switch self {
        case .green: return .systemGreen
        case .likelyFree: return .systemGreen.withAlphaComponent(0.45)
        case .yellow: return .systemYellow
        case .red: return .systemRed
        case .unknown: return .systemGray
        }
    }
}

#Preview {
    CoverageMapView()
        .environmentObject(AppModel())
}
