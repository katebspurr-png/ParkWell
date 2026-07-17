import Combine
import CoreLocation
import Foundation

/// Wraps CLLocationManager and publishes locations while the user drives.
///
/// Battery strategy (see docs/ARCHITECTURE.md): high-accuracy navigation
/// updates only while inside the mapped coverage area; drop to
/// significant-location-change monitoring outside it, so cruising around
/// Bedford doesn't burn the battery for zones we haven't mapped.
final class LocationService: NSObject, ObservableObject {
    @Published private(set) var location: CLLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()

    /// Bounding box of the loaded rule data (plus margin), set by AppModel
    /// once segments load; high-accuracy GPS runs only inside it. The default
    /// covers downtown Halifax + Dartmouth until data arrives.
    var coverageArea = (minLat: 44.630, maxLat: 44.680, minLon: -63.610, maxLon: -63.550)

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 10
        manager.pausesLocationUpdatesAutomatically = true
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func startTracking() {
        // While-Using permission is enough for background updates as long as
        // tracking starts in the foreground (the app has the `location`
        // background mode). Gating this on Always — as an earlier version
        // did — silently froze the pipeline when the phone locked in the car.
        let authorized = authorizationStatus == .authorizedWhenInUse
            || authorizationStatus == .authorizedAlways
        manager.allowsBackgroundLocationUpdates = authorized
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    func stopTracking() {
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
    }

    func isInCoverageArea(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.latitude >= coverageArea.minLat && coordinate.latitude <= coverageArea.maxLat
            && coordinate.longitude >= coverageArea.minLon && coordinate.longitude <= coverageArea.maxLon
    }

    private func adjustPowerMode(for coordinate: CLLocationCoordinate2D) {
        if isInCoverageArea(coordinate) {
            if manager.desiredAccuracy != kCLLocationAccuracyBestForNavigation {
                manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
                manager.startUpdatingLocation()
                manager.stopMonitoringSignificantLocationChanges()
            }
        } else if manager.desiredAccuracy == kCLLocationAccuracyBestForNavigation {
            manager.desiredAccuracy = kCLLocationAccuracyKilometer
            manager.startMonitoringSignificantLocationChanges()
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            startTracking()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        location = latest
        adjustPowerMode(for: latest.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient GPS failures are routine downtown; keep the last fix and
        // let staleness handling in the UI cover extended outages.
    }
}
