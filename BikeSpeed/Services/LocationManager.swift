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
    /// Whether `course` is currently being refreshed by fixes, i.e. the rider is moving fast enough for GPS
    /// course to mean anything. This has to be its own flag: `course` is deliberately *sticky*, holding its
    /// last value at a standstill rather than jittering, so it is never nil once set and `course ?? heading`
    /// could never fall back to the compass.
    private(set) var isCourseLive = false
    private(set) var altitude: Double?
    private(set) var coordinate: CLLocationCoordinate2D?
    private(set) var hasFix: Bool = false
    private(set) var signalQuality: GPSSignalQuality = .poor
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// Fixes that passed the accuracy filter, for `TripManager` and `AddressLookupManager` to consume.
    ///
    /// **Stays a Combine subject under `@Observable`, deliberately.** An accepted fix is an *event*;
    /// Observation observes *state*, and two consecutive identical fixes are a real thing a rider at a
    /// standstill produces constantly — there is no property whose change means "a fix arrived". It is
    /// also what keeps delivery *synchronous*: `TripManager.consume(_:)` runs inside `process(_:)`, which
    /// is why a test can move the rider and assert distance on the very next line without an `await`.
    /// An `AsyncStream` would make that asynchronous and buy nothing.
    let acceptedLocations = PassthroughSubject<CLLocation, Never>()

    /// **The direction the rider is actually travelling**, which is not the same question as either sensor
    /// answers alone.
    ///
    /// While moving, that is the GPS course: it is the true direction of travel and, unlike the compass,
    /// immune to how the phone is clamped to the bars. But course is noise below `courseSpeedThreshold`, so
    /// it is held there rather than jittered — which leaves the arrow pointing at wherever the rider was
    /// last heading, stale at every red light. The magnetometer fills exactly that gap: standing still, the
    /// way the bike is *pointing* is the best available answer to which way it's about to go.
    ///
    /// Falls back to the last course where there is no magnetometer at all (the Simulator), which is simply
    /// the behaviour this property replaces.
    var travelDirection: Double? {
        isCourseLive ? course : (heading ?? course)
    }

    private let manager = CLLocationManager()
    /// Smoothed on the unit circle, not in degrees — a plain average of 359° and 1° is due *south*. See
    /// `CircularMean`; that is the entire reason it exists. Untracked: it is the filter's internal state,
    /// and `heading` — which is what anyone actually draws — is the observable answer it produces.
    @ObservationIgnored private var headingSmoother = CircularMean(smoothingFactor: 0.25)
    private let smoothingFactor = 0.35
    /// Upper bound on horizontal accuracy for the green "good" band; up to `maxHorizontalAccuracy`
    /// is the yellow "fair" band. Worse than that is red "poor" and the fix is rejected.
    private let goodHorizontalAccuracy: CLLocationAccuracy = 10
    private let maxHorizontalAccuracy: CLLocationAccuracy = 30
    private let courseSpeedThreshold: CLLocationSpeed = 1.0 // m/s (~3.6 km/h) below which GPS course is noise
    /// Narrowest the standstill deadband is allowed to get (see `process`), and the width used for fixes
    /// that report no speed accuracy at all. ~1.8 km/h: below that you are pushing the bike, not riding it.
    private let standstillSpeedFloor: CLLocationSpeed = 0.5 // m/s
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
        // Guarded, not assumed: there is no magnetometer in the Simulator, and calling this there would only
        // wait for callbacks that never come. `travelDirection` degrades to course-only in that case.
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

        // GPS speed doesn't settle at zero when the bike does: it wanders a few tenths of a m/s, which
        // the gauge draws as a needle creeping up to 1–2 km/h and back with the bike parked. Smoothing
        // can't help — the noise is in the input. `speedAccuracy` is CoreLocation's own error bar on the
        // speed it just reported, so a reading inside it is indistinguishable from standing still, and
        // the deadband widens exactly when the fix turns noisy (indoors, in a street canyon) rather than
        // guessing one width for every condition. Bounded at both ends: never narrower than the floor,
        // since a fix reporting no speed accuracy sets it negative, and never wider than the threshold
        // this file already treats as the line below which GPS is noise, so a pessimistic error bar
        // cannot swallow a real ride. The negative "speed unknown" sentinel falls out of the same rule.
        let speedNoiseFloor = min(max(location.speedAccuracy, standstillSpeedFloor), courseSpeedThreshold)
        rawSpeed = location.speed <= speedNoiseFloor ? 0 : location.speed
        displaySpeed = smoothingFactor * rawSpeed + (1 - smoothingFactor) * displaySpeed

        let courseIsReliable = location.course >= 0 && (location.courseAccuracy < 0 || location.courseAccuracy <= 90)
        isCourseLive = courseIsReliable && rawSpeed >= courseSpeedThreshold
        if isCourseLive {
            course = location.course
        }
        // else: leave `course` at its last valid value rather than snapping/jittering. `isCourseLive` is what
        // records that it's now stale, so `travelDirection` knows to ask the compass instead.

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

    /// **Never.** A calibration modal — "wave your phone in a figure of eight" — thrown up over the gauge on
    /// a phone clamped to the handlebars of a moving bike is not something the rider can act on, and not
    /// something they should be asked to. A stale arrow is a far smaller problem than a dialog mid-ride.
    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        false
    }

    /// Internal, and taking plain degrees rather than the `CLHeading` the delegate got, for the same reason
    /// `process(_:)` is: this is where the logic lives, and `CLHeading` has no public initializer — a test
    /// could not build one to drive the delegate with.
    func process(
        trueHeading: CLLocationDirection,
        magneticHeading: CLLocationDirection,
        accuracy: CLLocationDirectionAccuracy
    ) {
        // Negative accuracy means the reading is unusable — CoreLocation's way of saying the magnetometer
        // is being interfered with, which near a bike's own frame and a phone's own speaker is not rare.
        guard accuracy >= 0 else { return }

        // `trueHeading` is geographic north and is what we want — but it is *negative* until a location fix
        // exists to resolve magnetic declination, which is precisely the moment the rider first opens the app
        // at a standstill. Magnetic north is a few degrees off and entirely good enough to point an arrow.
        let bearing = trueHeading >= 0 ? trueHeading : magneticHeading
        guard bearing >= 0 else { return }

        heading = headingSmoother.add(bearing)
    }
}
