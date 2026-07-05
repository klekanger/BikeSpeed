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
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// Fixes that passed the accuracy filter, for TripManager to consume for distance accumulation.
    let acceptedLocations = PassthroughSubject<CLLocation, Never>()

    private let manager = CLLocationManager()
    private let smoothingFactor = 0.35
    private let maxHorizontalAccuracy: CLLocationAccuracy = 30
    private let courseSpeedThreshold: CLLocationSpeed = 1.0 // m/s (~3.6 km/h) below which GPS course is noise

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .otherNavigation
        manager.distanceFilter = kCLDistanceFilterNone
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

    private func process(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= maxHorizontalAccuracy else {
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
