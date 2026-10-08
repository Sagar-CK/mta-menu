import CoreLocation
import Foundation

/// Thin wrapper over `CLLocationManager` that exposes the latest fix and a
/// human-readable status for the menu.
///
/// macOS shows the location permission prompt only for a proper `.app` bundle
/// with `NSLocationUsageDescription` in its Info.plist, which is why the app is
/// run via `scripts/run.sh` rather than `swift run`.
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    private(set) var current: Coordinate?
    private(set) var statusText = "Requesting location access…"

    /// Called on the main thread whenever a new fix arrives.
    var onUpdate: ((Coordinate) -> Void)?

    func start() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
        handleAuthorization(manager.authorizationStatus)
    }

    private func handleAuthorization(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            statusText = "Requesting location access…"
            manager.requestWhenInUseAuthorization()
        case .denied:
            statusText = "Location access denied. Enable it in System Settings › Privacy & Security › Location Services, or set a location manually."
        case .restricted:
            statusText = "Location access is restricted on this Mac."
        default:
            statusText = "Locating…"
            manager.startUpdatingLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        handleAuthorization(manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let coordinate = Coordinate(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude)
        current = coordinate
        statusText = "Using Mac location (±\(Int(last.horizontalAccuracy)) m)"
        onUpdate?(coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if current == nil {
            statusText = "Location unavailable: \(error.localizedDescription)"
        }
    }
}
