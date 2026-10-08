import Foundation

/// User settings, persisted in `UserDefaults` (domain `com.sagarck.MTAMenu`).
///
/// Everything here can also be set from the shell, which is handy for testing:
/// ```
/// defaults write com.sagarck.MTAMenu selectedRoutes -array N A
/// defaults write com.sagarck.MTAMenu manualLatitude -float 40.758
/// defaults write com.sagarck.MTAMenu manualLongitude -float -73.9855
/// defaults write com.sagarck.MTAMenu refreshInterval -int 20
/// defaults write com.sagarck.MTAMenu nearbyRadiusMeters -int 800
/// ```
final class Preferences {
    static let shared = Preferences()

    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Lines to listen to. Empty means "all lines".
    var selectedRoutes: Set<String> {
        get { Set(defaults.stringArray(forKey: "selectedRoutes") ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: "selectedRoutes") }
    }

    /// Overrides the Mac's location when set (useful off-Wi-Fi or outside NYC).
    var manualLocation: Coordinate? {
        get {
            guard defaults.object(forKey: "manualLatitude") != nil,
                  defaults.object(forKey: "manualLongitude") != nil else { return nil }
            return Coordinate(latitude: defaults.double(forKey: "manualLatitude"),
                              longitude: defaults.double(forKey: "manualLongitude"))
        }
        set {
            if let c = newValue {
                defaults.set(c.latitude, forKey: "manualLatitude")
                defaults.set(c.longitude, forKey: "manualLongitude")
            } else {
                defaults.removeObject(forKey: "manualLatitude")
                defaults.removeObject(forKey: "manualLongitude")
            }
        }
    }

    /// Only show followed lines with a station within this many meters of you
    /// (the closest station is always shown). `nil` means no limit.
    /// Default 800 m, about a 10-minute walk.
    var nearbyRadiusMeters: Double? {
        get {
            guard defaults.object(forKey: "nearbyRadiusMeters") != nil else { return 800 }
            let value = defaults.double(forKey: "nearbyRadiusMeters")
            return value > 0 ? value : nil
        }
        set { defaults.set(newValue ?? 0, forKey: "nearbyRadiusMeters") }
    }

    /// Seconds between feed refreshes. The MTA updates feeds roughly every 30 s.
    var refreshInterval: TimeInterval {
        let value = defaults.integer(forKey: "refreshInterval")
        return value >= 10 ? TimeInterval(value) : 30
    }
}
