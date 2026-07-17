import Combine
import CoreLocation
import Foundation

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
    @Published private(set) var isDriving = false
    @Published var cueStyleRaw: String {
        didSet { UserDefaults.standard.set(cueStyleRaw, forKey: "cueStyle") }
    }

    let locationService = LocationService()
    private let repository = RulesRepository()
    private let matcher = SegmentMatcher()
    private let engine = RuleEngine()
    private let audio = AudioCueService()
    private let liveActivity = LiveActivityController()

    private var cancellables: Set<AnyCancellable> = []
    private var segments: [StreetSegment] = []
    private var payStations: [PayStation] = []
    private var overlays: DynamicOverlays?
    private var overlayRefreshTask: Task<Void, Never>?

    var cueStyle: AudioCueService.CueStyle {
        AudioCueService.CueStyle(rawValue: cueStyleRaw) ?? .spoken
    }

    init() {
        cueStyleRaw = UserDefaults.standard.string(forKey: "cueStyle")
            ?? AudioCueService.CueStyle.spoken.rawValue
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
        scheduleOverlayRefresh()
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
        let segment = matcher.nearestSegment(to: location.coordinate, in: segments)
        let station = nearestPayStation(to: location, maxDistanceMeters: 120)
        let newVerdict = engine.verdict(segment: segment, overlays: overlays,
                                        nearestPayStation: station, at: Date())

        let changed = newVerdict.headline != verdict?.headline || newVerdict.level != verdict?.level
        currentSegment = segment
        verdict = newVerdict

        guard isDriving else { return }
        liveActivity.isActive ? liveActivity.update(with: newVerdict) : liveActivity.start(with: newVerdict)
        if changed {
            audio.announce(newVerdict, style: cueStyle)
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
            }
        }
    }
}
