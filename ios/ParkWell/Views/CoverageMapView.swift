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

    /// Downtown Halifax, for when there's no location fix yet.
    private let fallbackRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 44.6488, longitude: -63.5752),
        span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)
    )

    var body: some View {
        NavigationStack {
            Map(initialPosition: .userLocation(fallback: .region(fallbackRegion))) {
                UserAnnotation()

                ForEach(model.segments) { segment in
                    MapPolyline(coordinates: segment.polyline.map {
                        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                    })
                    .stroke(color(for: levels[segment.id] ?? .unknown), lineWidth: 4)
                }

                ForEach(model.payStations) { station in
                    MapCircle(center: CLLocationCoordinate2D(latitude: station.latitude,
                                                             longitude: station.longitude),
                              radius: 6)
                        .foregroundStyle(.purple)
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
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

    private func color(for level: StatusLevel) -> Color {
        switch level {
        case .green: return .green
        case .likelyFree: return .green.opacity(0.45)
        case .yellow: return .yellow
        case .red: return .red
        case .unknown: return .gray
        }
    }
}

#Preview {
    CoverageMapView()
        .environmentObject(AppModel())
}
