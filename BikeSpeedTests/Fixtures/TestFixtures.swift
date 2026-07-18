import Combine
import CoreLocation
import Foundation
import Testing

@testable import BikeSpeed

/// A wall clock the test drives by hand. `TripManager` takes its `now` from this, so elapsed time and
/// the auto-pause fix-loss watchdog can be exercised without a single `sleep`.
final class TestClock {
    private(set) var now: Date

    init(start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        now = start
    }

    func advance(_ seconds: TimeInterval) {
        now += seconds
    }
}

enum Fix {
    static let oslo = CLLocationCoordinate2D(latitude: 59.9139, longitude: 10.7522)

    /// A coordinate `meters` due north of `from`. A degree of latitude is ~111.32 km everywhere, so
    /// this is exact to well under the tolerances any of these tests assert on.
    static func north(of from: CLLocationCoordinate2D, meters: CLLocationDistance) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: from.latitude + meters / 111_320, longitude: from.longitude)
    }
}

/// A `CLLocation` with every field the filters look at under the test's control. The defaults describe
/// an unremarkable good fix — a rider heading east at 8 m/s with clean accuracy — so each test only has
/// to name the one thing it is actually about.
func makeFix(
    coordinate: CLLocationCoordinate2D = Fix.oslo,
    altitude: CLLocationDistance = 100,
    horizontalAccuracy: CLLocationAccuracy = 5,
    verticalAccuracy: CLLocationAccuracy = 5,
    course: CLLocationDirection = 90,
    courseAccuracy: CLLocationDirectionAccuracy = 5,
    speed: CLLocationSpeed = 8,
    speedAccuracy: CLLocationSpeedAccuracy = 1,
    timestamp: Date = Date()
) -> CLLocation {
    CLLocation(
        coordinate: coordinate,
        altitude: altitude,
        horizontalAccuracy: horizontalAccuracy,
        verticalAccuracy: verticalAccuracy,
        course: course,
        courseAccuracy: courseAccuracy,
        speed: speed,
        speedAccuracy: speedAccuracy,
        timestamp: timestamp
    )
}

/// Stands in for `LocationManager` on the `LocationSource` seam. Fixes go straight into the subject —
/// the trip tests were never about the GPS filtering, which has its own suite — and every background-
/// updates request is recorded so tests can assert on what `TripManager` asked for, not on CoreLocation.
@MainActor
final class FakeLocationSource: LocationSource {
    let acceptedLocations = PassthroughSubject<CLLocation, Never>()
    private(set) var backgroundUpdatesEnabled = false

    func setBackgroundUpdates(_ enabled: Bool) {
        backgroundUpdatesEnabled = enabled
    }
}

/// Stands in for `AltimeterManager` on the `AltitudeSource` seam. There is nothing to subscribe to:
/// `TripManager` samples `relativeAltitude` at each accepted fix, so a test just sets it between moves.
/// `isAvailable` is a var because the real manager drops it when updates start erroring (a denied
/// Motion & Fitness permission) — tests flip it to simulate that failure.
@MainActor
final class FakeAltitudeSource: AltitudeSource {
    var isAvailable: Bool
    var relativeAltitude: Double?
    private(set) var isUpdating = false

    init(isAvailable: Bool) {
        self.isAvailable = isAvailable
    }

    func startUpdates() {
        isUpdating = true
    }

    func stopUpdates() {
        isUpdating = false
        // Mirrors `AltimeterManager`: relative altitude is zeroed wherever updates start, so a
        // reading from before the stop must never be readable afterwards.
        relativeAltitude = nil
    }
}

/// Drives a `TripManager` the way a ride does: fixes arrive from the location source's accepted-fix
/// subject, and the clock moves only when the test says so.
///
/// `move(meters:)` is the primary verb — it advances the clock, walks the rider north, and feeds in the
/// resulting fix, which keeps the tests reading as statements about riding rather than about CoreLocation.
@MainActor
final class TripTestHarness {
    let clock = TestClock()
    let locationSource = FakeLocationSource()
    /// Unavailable by default, so a plain harness rides the GPS-altitude fallback — the fixes already
    /// carry an altitude — and only the barometer-specific tests opt in to the barometer.
    let altimeter: FakeAltitudeSource
    let settings: SettingsStore
    let trip: TripManager

    private var coordinate = Fix.oslo
    private let suiteName: String

    init(autoPauseEnabled: Bool = true, barometerAvailable: Bool = false) {
        suiteName = "BikeSpeedTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        settings = SettingsStore(defaults: defaults)
        settings.autoPauseEnabled = autoPauseEnabled
        altimeter = FakeAltitudeSource(isAvailable: barometerAvailable)

        let clock = self.clock
        trip = TripManager(
            locationManager: locationSource,
            altimeter: altimeter,
            settings: settings,
            now: { clock.now }
        )
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    /// Advance time and move the rider, then deliver the fix that describes it.
    ///
    /// `speed` defaults to the speed the movement actually implies, which is what a real GPS reports.
    /// Tests that care about the *reported* speed differing from the *travelled* distance — the teleport
    /// and clamping cases — override it.
    ///
    /// Mind the implied speed: `meters / seconds` must stay under `TripManager`'s 120 km/h ceiling (33.3
    /// m/s) or the fix is discarded as a teleport and no distance accrues. `move(meters: 50)` at the default
    /// one second is 180 km/h, and will be thrown away — which is the guard working, not a bug.
    func move(
        meters: CLLocationDistance,
        seconds: TimeInterval = 1,
        speed: CLLocationSpeed? = nil,
        altitude: CLLocationDistance = 100,
        horizontalAccuracy: CLLocationAccuracy = 5,
        verticalAccuracy: CLLocationAccuracy = 5
    ) {
        clock.advance(seconds)
        coordinate = Fix.north(of: coordinate, meters: meters)
        send(makeFix(
            coordinate: coordinate,
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            speed: speed ?? (meters / seconds),
            timestamp: clock.now
        ))
    }

    /// Deliver a fix without moving or advancing time — used to drop the initial anchor, since the first
    /// fix a trip ever sees only establishes where distance is measured *from*.
    func anchor() {
        send(makeFix(coordinate: coordinate, speed: 0, timestamp: clock.now))
    }

    func send(_ location: CLLocation) {
        locationSource.acceptedLocations.send(location)
    }
}

/// A fixed calendar date at noon in `calendar` — the shape every date-driven suite builds its cases from.
/// Noon keeps a case from sliding across midnight when the calendar isn't UTC.
func date(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar) throws -> Date {
    try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
}

/// A UTC Gregorian calendar, so no case turns on the machine's time zone shifting a date across midnight.
/// `firstWeekday` defaults to Monday (Norway) — the week/month suites pass it explicitly, the range/month
/// suites don't depend on it.
func calendar(firstWeekday: Int = 2) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    calendar.firstWeekday = firstWeekday
    return calendar
}

/// Distances and speeds here come out of geodesy and floating-point accumulation, so they are compared
/// with a tolerance. Failures print both values, which is what you want when one is 49.97.
func expectClose(
    _ actual: Double,
    _ expected: Double,
    within tolerance: Double = 0.5,
    _ comment: Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(
        abs(actual - expected) <= tolerance,
        comment ?? "expected \(expected) ± \(tolerance), got \(actual)",
        sourceLocation: sourceLocation
    )
}
