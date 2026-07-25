import Combine
import CoreLocation
import Observation

/// Wraps CLLocationManager, publishing filtered/smoothed speed, course, altitude, and position.
/// All published values are in SI units (m/s, meters, degrees) — unit conversion happens only in views.
@MainActor
@Observable
final class LocationManager: NSObject {
    private(set) var rawSpeed: Double = 0
    private(set) var displaySpeed: Double = 0
    private(set) var course: Double?
    /// The magnetometer, smoothed circularly (see `CircularMean`). Nil where there is no magnetometer —
    /// the Simulator — and until the first usable reading arrives.
    private(set) var heading: Double?
    /// Whether `course` is currently refreshed by fixes (rider moving fast enough for GPS course to mean
    /// anything). Needs its own flag because `course` is *sticky* — it holds its last value at a standstill
    /// rather than nilling, so `course ?? heading` alone could never fall back to the compass.
    private(set) var isCourseLive = false
    private(set) var altitude: Double?
    private(set) var coordinate: CLLocationCoordinate2D?
    private(set) var hasFix: Bool = false
    private(set) var signalQuality: GPSSignalQuality = .poor
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// Fixes that passed the accuracy filter, for `TripManager` and `AddressLookupManager` to consume.
    ///
    /// **Deliberately a Combine subject, not `@Observable` state.** An accepted fix is an *event* (a
    /// standstill rider emits identical fixes constantly — no state change means "a fix arrived"). It also
    /// keeps delivery *synchronous*: `TripManager.consume(_:)` runs inside `process(_:)`, so a test can move
    /// the rider and assert distance on the next line without an `await`. An `AsyncStream` would break that.
    let acceptedLocations = PassthroughSubject<CLLocation, Never>()

    /// **The direction the rider is actually travelling** — not the same question either sensor answers alone.
    ///
    /// Moving: GPS course, the true travel direction and, unlike the compass, immune to how the phone is
    /// clamped to the bars. Below `courseSpeedThreshold` course is noise and held sticky, so the arrow would
    /// go stale at every red light; the magnetometer fills that gap (the way the bike *points* is the best
    /// guess at where it's about to go). Falls back to the last course where there's no magnetometer (Simulator).
    var travelDirection: Double? {
        isCourseLive ? course : (heading ?? course)
    }

    private let manager = CLLocationManager()
    /// Smoothed on the unit circle, not in degrees — a plain average of 359° and 1° is due *south* (see
    /// `CircularMean`). Untracked: internal filter state; `heading` is the observable answer views draw.
    @ObservationIgnored private var headingSmoother = CircularMean(smoothingFactor: 0.25)
    private let smoothingFactor = 0.35
    /// "Good" (green) band ceiling; up to `maxHorizontalAccuracy` is "fair" (yellow). Worse is "poor"
    /// (red) and the fix is rejected.
    private let goodHorizontalAccuracy: CLLocationAccuracy = 10
    private let maxHorizontalAccuracy: CLLocationAccuracy = 30
    private let courseSpeedThreshold: CLLocationSpeed = 1.0 // m/s (~3.6 km/h) below which GPS course is noise
    /// Floor for the standstill deadband (see `process`), and the width for fixes reporting no speed
    /// accuracy. ~1.8 km/h: below that you're pushing the bike, not riding it.
    private let standstillSpeedFloor: CLLocationSpeed = 0.5 // m/s
    /// How old a fix may be and still count as current. Filtered separately from accuracy because
    /// `startUpdatingLocation()` replays the last cached fix immediately — minutes old yet with excellent
    /// `horizontalAccuracy`, so the accuracy filter waves it through. Downstream reads `timestamp` as "now"
    /// (`TripManager` measures both its auto-pause debounce and `dt` against it).
    private let maxFixAge: TimeInterval = 5

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .otherNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        // Defaults to true; with `.otherNavigation`, iOS then pauses updates when it thinks the rider
        // stopped and never resumes — presenting as a mid-ride freeze. Stopping is `TripManager`'s call
        // (auto-pause), not the OS's.
        manager.pausesLocationUpdatesAutomatically = false
        authorizationStatus = manager.authorizationStatus
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdating() {
        manager.startUpdatingLocation()
        // Guarded: no magnetometer in the Simulator, where this would only await callbacks that never come.
        // `travelDirection` degrades to course-only there.
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }
}

extension LocationManager: LocationSource {
    /// Requires `UIBackgroundModes = location` — setting this without the capability crashes at runtime, so
    /// the two ship together (the key lives in the partial `Info.plist` at the repo root; no working
    /// `INFOPLIST_KEY_*` equivalent). WhenInUse auth suffices; the indicator flag keeps iOS showing the
    /// location pill while recording under a locked screen.
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

    /// Internal, not private, so tests drive the filter directly. All filtering lives here; the delegate
    /// callback only hops onto the main actor and calls it, so driving via the delegate would race that
    /// `Task` for nothing.
    func process(_ location: CLLocation) {
        // A cached fix reports where the phone *was*; drop it before it poses as current. Ahead of
        // everything and without touching `hasFix` — a stale fix isn't a signal-quality problem, and
        // letting it drive the indicator would flash the state of a fix we're about to ignore.
        guard Date().timeIntervalSince(location.timestamp) <= maxFixAge else { return }

        signalQuality = GPSSignalQuality(
            horizontalAccuracy: location.horizontalAccuracy,
            goodWithin: goodHorizontalAccuracy,
            acceptableWithin: maxHorizontalAccuracy
        )

        // Poor signal: freeze speed/course/altitude/position at their last trusted values and don't emit,
        // so TripManager adds nothing to distance either.
        guard signalQuality.isUsable else {
            hasFix = false
            return
        }
        hasFix = true

        // GPS speed doesn't settle at zero when the bike does — it wanders a few tenths of a m/s, drawn as
        // the needle creeping to 1–2 km/h and back while parked; smoothing can't help, the noise is in the
        // input. `speedAccuracy` is CoreLocation's own error bar on that speed, so a reading inside it is
        // indistinguishable from standstill, and the deadband widens exactly when the fix turns noisy
        // (indoors, street canyon) instead of one fixed width. Bounded both ends: never below the floor
        // (a no-accuracy fix reports negative), never above `courseSpeedThreshold` (GPS-is-noise line), so
        // a pessimistic error bar can't swallow a real ride. The negative "unknown" sentinel falls out too.
        let speedNoiseFloor = min(max(location.speedAccuracy, standstillSpeedFloor), courseSpeedThreshold)
        rawSpeed = location.speed <= speedNoiseFloor ? 0 : location.speed
        displaySpeed = smoothingFactor * rawSpeed + (1 - smoothingFactor) * displaySpeed

        let courseIsReliable = location.course >= 0 && (location.courseAccuracy < 0 || location.courseAccuracy <= 90)
        isCourseLive = courseIsReliable && rawSpeed >= courseSpeedThreshold
        if isCourseLive {
            course = location.course
        }
        // else: hold `course` at its last valid value. `isCourseLive` records it's now stale, so
        // `travelDirection` knows to ask the compass instead.

        if let usableAltitude = location.usableAltitude() {
            altitude = usableAltitude
        }

        coordinate = location.coordinate
        acceptedLocations.send(location)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let trueHeading = newHeading.trueHeading
        let magneticHeading = newHeading.magneticHeading
        let accuracy = newHeading.headingAccuracy
        Task { @MainActor in
            self.process(trueHeading: trueHeading, magneticHeading: magneticHeading, accuracy: accuracy)
        }
    }

    /// **Never.** A "wave your phone in a figure of eight" modal over the gauge, on a phone clamped to the
    /// bars of a moving bike, isn't something the rider can act on. A stale arrow beats a dialog mid-ride.
    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        false
    }

    /// Internal, and takes plain degrees rather than `CLHeading`, for the same reason as `process(_:)`: the
    /// logic lives here, and `CLHeading` has no public initializer for a test to build.
    func process(
        trueHeading: CLLocationDirection,
        magneticHeading: CLLocationDirection,
        accuracy: CLLocationDirectionAccuracy
    ) {
        // Negative accuracy = unusable: CoreLocation's signal that the magnetometer is being interfered
        // with, not rare near a bike frame and a phone speaker.
        guard accuracy >= 0 else { return }

        // `trueHeading` (geographic north) is what we want, but it's *negative* until a location fix resolves
        // magnetic declination — exactly when the rider first opens the app at a standstill. Magnetic north
        // is a few degrees off and good enough to point an arrow.
        let bearing = trueHeading >= 0 ? trueHeading : magneticHeading
        guard bearing >= 0 else { return }

        heading = headingSmoother.add(bearing)
    }
}
