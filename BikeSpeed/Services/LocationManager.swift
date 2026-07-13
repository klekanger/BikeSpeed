import CoreLocation
import Combine

/// Wraps CLLocationManager, publishing filtered/smoothed speed, course, altitude, and position.
/// All published values are in SI units (m/s, meters, degrees) — unit conversion happens only in views.
@MainActor
final class LocationManager: NSObject, ObservableObject {
    @Published private(set) var rawSpeed: Double = 0
    @Published private(set) var displaySpeed: Double = 0
    @Published private(set) var course: Double?
    @Published private(set) var altitude: Double?
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var hasFix: Bool = false
    @Published private(set) var signalQuality: GPSSignalQuality = .poor
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// Fixes that passed the accuracy filter, for TripManager to consume for distance accumulation.
    let acceptedLocations = PassthroughSubject<CLLocation, Never>()

    private let manager = CLLocationManager()
    private let smoothingFactor = 0.35
    /// Upper bound on horizontal accuracy for the green "good" band; up to `maxHorizontalAccuracy`
    /// is the yellow "fair" band. Worse than that is red "poor" and the fix is rejected.
    private let goodHorizontalAccuracy: CLLocationAccuracy = 10
    private let maxHorizontalAccuracy: CLLocationAccuracy = 30
    private let courseSpeedThreshold: CLLocationSpeed = 1.0 // m/s (~3.6 km/h) below which GPS course is noise
    /// How old a fix may be and still be treated as current. Age has to be filtered separately from
    /// accuracy: `startUpdatingLocation()` replays the last cached fix immediately, and that fix can
    /// be minutes old while still carrying excellent `horizontalAccuracy`, so the accuracy filter
    /// below waves it straight through. Everything downstream reads `timestamp` as "now" — see
    /// `TripManager`, which measures both its auto-pause debounce and its `dt` against it.
    private let maxFixAge: TimeInterval = 5

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .otherNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        // Defaults to true — and with `activityType = .otherNavigation`, iOS pauses updates when it
        // decides the rider has stopped and never resumes them, which presents as the app freezing
        // mid-ride. The stopping decision is `TripManager`'s (auto-pause), not the OS's.
        manager.pausesLocationUpdatesAutomatically = false
        authorizationStatus = manager.authorizationStatus
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdating() {
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
    }
}

extension LocationManager: LocationSource {
    /// Requires `UIBackgroundModes = location` — setting this without the capability is a runtime
    /// crash, so the two ship together (the key lives in the partial `Info.plist` at the repo root;
    /// it has no working `INFOPLIST_KEY_*` equivalent). WhenInUse authorization is sufficient; the
    /// indicator flag keeps iOS showing the location pill while recording continues under a locked
    /// screen, which is the honest thing to do.
    func setBackgroundUpdates(_ enabled: Bool) {
        manager.allowsBackgroundLocationUpdates = enabled
        manager.showsBackgroundLocationIndicator = enabled
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.startUpdating()
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.process(location)
        }
    }

    /// Internal rather than private so tests can drive the filter directly. This is where all of the
    /// filtering actually lives; the delegate callback above only hops onto the main actor and calls it,
    /// so going in through the delegate would mean racing that `Task` for nothing.
    func process(_ location: CLLocation) {
        // A cached fix reports where the phone *was*, so drop it before it can pose as a current
        // reading. Deliberately ahead of everything else and without touching `hasFix`: a stale fix
        // is not a signal-quality problem, and letting it drive the indicator would flash the state
        // of a fix we're about to ignore anyway.
        guard Date().timeIntervalSince(location.timestamp) <= maxFixAge else { return }

        signalQuality = GPSSignalQuality(
            horizontalAccuracy: location.horizontalAccuracy,
            goodWithin: goodHorizontalAccuracy,
            acceptableWithin: maxHorizontalAccuracy
        )

        // Poor signal: leave speed/course/altitude/position frozen at their last trusted values and
        // don't emit the fix, so TripManager adds nothing to the recorded distance either.
        guard signalQuality.isUsable else {
            hasFix = false
            return
        }
        hasFix = true

        rawSpeed = location.speed < 0 ? 0 : location.speed
        displaySpeed = smoothingFactor * rawSpeed + (1 - smoothingFactor) * displaySpeed

        let courseIsReliable = location.course >= 0 && (location.courseAccuracy < 0 || location.courseAccuracy <= 90)
        if courseIsReliable && rawSpeed >= courseSpeedThreshold {
            course = location.course
        }
        // else: leave `course` at its last valid value rather than snapping/jittering.

        if location.verticalAccuracy >= 0 {
            altitude = location.altitude
        }

        coordinate = location.coordinate
        acceptedLocations.send(location)
    }
}
