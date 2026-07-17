import Combine
import CoreLocation
import Foundation
import MapKit

/// Central coordinator: location → segment match → verdict → surfaces.
///
/// The pipeline runs on every location update, but the audio cue and Live
/// Activity only fire when the driver crosses into a *different* rule state —
/// that's the whole product: status computed before you need it, delivered
/// once, at the moment it changes.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var verdict: Verdict?
    @Published private(set) var currentSegment: StreetSegment?
    /// "Likely parking ~200 m away on Maynard St" — set when the current
    /// street isn't parkable and a nearby one is.
    @Published private(set) var suggestion: String?
    @Published private(set) var isDriving = false
    @Published var cueStyleRaw: String {
        didSet { UserDefaults.standard.set(cueStyleRaw, forKey: "cueStyle") }
    }
    @Published var preferenceRaw: String {
        didSet { UserDefaults.standard.set(preferenceRaw, forKey: "parkingPreference") }
    }

    let locationService = LocationService()
    private let repository = RulesRepository()
    private let matcher = SegmentMatcher()
    private let engine = RuleEngine()
    private let suggestionEngine = SuggestionEngine()
    private let audio = AudioCueService()
    private let liveActivity = LiveActivityController()

    private var cancellables: Set<AnyCancellable> = []
    private var segmentIndex = SegmentIndex()
    @Published private(set) var segments: [StreetSegment] = []
    @Published private(set) var payStations: [PayStation] = []
    @Published private(set) var overlays: DynamicOverlays?
    private var zoneRates: [String: [ZoneRateWindow]] = [:]
    private var overlayRefreshTask: Task<Void, Never>?

    /// Nearby garages/lots from MapKit local search. On-device only — never
    /// sent to the backend (Apple ToS).
    private struct Garage {
        var name: String
        var latitude: Double
        var longitude: Double
    }
    private var garages: [Garage] = []
    private var lastGarageSearchLocation: CLLocation?

    var cueStyle: AudioCueService.CueStyle {
        AudioCueService.CueStyle(rawValue: cueStyleRaw) ?? .spoken
    }

    var preference: ParkingPreference {
        ParkingPreference(rawValue: preferenceRaw) ?? .cheapestFirst
    }

    init() {
        cueStyleRaw = UserDefaults.standard.string(forKey: "cueStyle")
            ?? AudioCueService.CueStyle.spoken.rawValue
        preferenceRaw = UserDefaults.standard.string(forKey: "parkingPreference")
            ?? ParkingPreference.cheapestFirst.rawValue
        locationService.$location
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] location in
                self?.handle(location: location)
            }
            .store(in: &cancellables)
    }

    func start() async {
        locationService.requestAuthorization()
        await repository.load()
        segments = await repository.segments
        payStations = await repository.payStations
        overlays = await repository.overlays
        zoneRates = await repository.zoneRates
        segmentIndex = SegmentIndex(segments: segments)
        updateCoverageArea()
        scheduleOverlayRefresh()
    }

    /// High-accuracy GPS should run wherever we actually have data — derive
    /// the bounds from the loaded segments (~1 km margin) instead of a
    /// hardcoded downtown box.
    private func updateCoverageArea() {
        let coords = segments.flatMap(\.polyline)
        guard let first = coords.first else { return }
        var bounds = (minLat: first.latitude, maxLat: first.latitude,
                      minLon: first.longitude, maxLon: first.longitude)
        for c in coords {
            bounds.minLat = min(bounds.minLat, c.latitude)
            bounds.maxLat = max(bounds.maxLat, c.latitude)
            bounds.minLon = min(bounds.minLon, c.longitude)
            bounds.maxLon = max(bounds.maxLon, c.longitude)
        }
        let margin = 0.01  // ≈1 km
        locationService.coverageArea = (bounds.minLat - margin, bounds.maxLat + margin,
                                        bounds.minLon - margin, bounds.maxLon + margin)
    }

    func startDrive() {
        isDriving = true
        locationService.startTracking()
        if let verdict {
            liveActivity.start(with: verdict)
        }
    }

    func endDrive() {
        isDriving = false
        locationService.stopTracking()
        liveActivity.end()
    }

    // MARK: - Pipeline

    private func handle(location: CLLocation) {
        let now = Date()
        let segment = matcher.nearestSegment(
            to: location.coordinate,
            in: segmentIndex.candidates(near: location.coordinate)
        )
        let station = nearestPayStation(to: location, maxDistanceMeters: 120)
        var newVerdict = engine.verdict(segment: segment, overlays: overlays,
                                        nearestPayStation: station,
                                        zoneRates: zoneRates, at: now)

        // "Closest right now": when you can't park here, point at the best
        // alternative for the user's preference — free/cheapest/nearest.
        let nearby = newVerdict.level.isParkable
            ? nil
            : bestSuggestion(near: location, excluding: segment?.streetName, at: now)
        suggestion = nearby?.line
        if let nearby, newVerdict.level == .red {
            newVerdict.spoken += " " + nearby.spoken
        }

        let changed = newVerdict.headline != verdict?.headline || newVerdict.level != verdict?.level
        currentSegment = segment
        verdict = newVerdict

        guard isDriving else { return }
        liveActivity.isActive ? liveActivity.update(with: newVerdict) : liveActivity.start(with: newVerdict)
        if changed {
            audio.announce(newVerdict, style: cueStyle)
        }
    }

    private func bestSuggestion(near location: CLLocation, excluding streetName: String?,
                                at date: Date) -> (line: String, spoken: String)? {
        var streets: [SuggestionEngine.StreetCandidate] = []
        // cellRadius 2 ≈ ≥790 m guaranteed — superset of the 500 m cutoff.
        for segment in segmentIndex.candidates(near: location.coordinate, cellRadius: 2) {
            guard segment.streetName != streetName else { continue }
            guard let d = matcher.distance(from: location.coordinate, toPolyline: segment.polyline),
                  d > 25, d < 500 else { continue }
            let verdict = engine.verdict(segment: segment, overlays: overlays,
                                         zoneRates: zoneRates, at: date)
            if verdict.level.isParkable {
                streets.append(.init(name: segment.streetName, meters: d,
                                     isFree: true, hourlyRateCents: nil))
            } else if verdict.level == .yellow,
                      segment.rules.contains(where: { $0.kind == .paid && $0.isActive(at: date, calendar: engine.calendar) }) {
                streets.append(.init(name: segment.streetName, meters: d,
                                     isFree: false, hourlyRateCents: verdict.hourlyRateCents))
            }
        }

        // Garages only enter the running when the preference allows them and
        // streets alone don't answer well nearby.
        let streetOnly = suggestionEngine.best(streets: streets, garages: [], mode: preference)
        if preference.allowsGarages, streetOnly.map({ $0.meters > 300 }) ?? true {
            refreshGaragesIfNeeded(around: location)
        }
        let garageCandidates = garages
            .map { garage in
                SuggestionEngine.GarageCandidate(
                    name: garage.name,
                    meters: location.distance(from: CLLocation(latitude: garage.latitude,
                                                               longitude: garage.longitude)))
            }
            .filter { $0.meters < 1000 }

        guard let best = suggestionEngine.best(streets: streets, garages: garageCandidates,
                                               mode: preference) else { return nil }
        switch best {
        case .street(let name, let meters, let isFree, let rate):
            let m = roundedMeters(meters)
            if isFree {
                return ("Likely parking ~\(m) m away on \(name)",
                        "Nearest likely parking: \(name), about \(m) meters.")
            }
            let rateText = rate.map { " · \(RuleEngine.dollarString($0))/hr" } ?? ""
            return ("Paid parking ~\(m) m away on \(name)\(rateText)",
                    "Nearest paid parking: \(name), about \(m) meters.")
        case .garage(let name, let meters):
            let m = roundedMeters(meters)
            return ("Nearest lot: \(name), \(m) m",
                    "Nearest lot: \(name), about \(m) meters.")
        }
    }

    /// Round to 50 m — GPS and polyline precision don't support better.
    private func roundedMeters(_ meters: Double) -> Int {
        max(50, Int((meters / 50).rounded() * 50))
    }

    /// One MapKit .parking search per ~200 m of travel, results reused
    /// in between — this runs during driving, so keep it quiet.
    private func refreshGaragesIfNeeded(around location: CLLocation) {
        if let last = lastGarageSearchLocation, location.distance(from: last) < 200 { return }
        lastGarageSearchLocation = location

        let request = MKLocalPointsOfInterestRequest(center: location.coordinate, radius: 1000)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.parking])
        Task { [weak self] in
            guard let response = try? await MKLocalSearch(request: request).start() else { return }
            guard let self else { return }
            self.garages = response.mapItems.compactMap { item in
                guard let name = item.name else { return nil }
                let coordinate = item.placemark.coordinate
                return Garage(name: name, latitude: coordinate.latitude,
                              longitude: coordinate.longitude)
            }
            // Re-rank promptly so the suggestion line picks up the results.
            if let current = self.locationService.location {
                self.handle(location: current)
            }
        }
    }

    private func nearestPayStation(to location: CLLocation, maxDistanceMeters: Double) -> PayStation? {
        payStations
            .map { station -> (PayStation, Double) in
                let stationLocation = CLLocation(latitude: station.latitude, longitude: station.longitude)
                return (station, location.distance(from: stationLocation))
            }
            .filter { $0.1 <= maxDistanceMeters }
            .min { $0.1 < $1.1 }?.0
    }

    /// The winter ban can flip mid-drive; poll the overlay every 15 minutes.
    private func scheduleOverlayRefresh() {
        overlayRefreshTask?.cancel()
        overlayRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15 * 60))
                guard let self else { return }
                await self.repository.refresh()
                self.segments = await self.repository.segments
                self.payStations = await self.repository.payStations
                self.overlays = await self.repository.overlays
                self.zoneRates = await self.repository.zoneRates
                self.segmentIndex = SegmentIndex(segments: self.segments)
            }
        }
    }
}
