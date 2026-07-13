import Combine
import CoreLocation
import Testing

@testable import BikeSpeed

/// Pins `LocationManager`'s two independent filters — accuracy and age — and the "freeze, don't zero"
/// policy they enforce. Everything downstream trusts an emitted fix completely, so these are the rules
/// that keep noise out of the gauge and out of the trip.
@Suite(.tags(.gps))
struct LocationManagerTests {

    @Test
    func aGoodFixIsAcceptedAndPublished() {
        let manager = LocationManager()
        var accepted: [CLLocation] = []
        let subscription = manager.acceptedLocations.sink { accepted.append($0) }
        defer { subscription.cancel() }

        manager.process(makeFix(speed: 8, timestamp: Date()))

        #expect(manager.hasFix)
        expectClose(manager.rawSpeed, 8, within: 0.01)
        #expect(accepted.count == 1)
        #expect(manager.coordinate != nil)
    }

    // MARK: - Age filter

    /// `startUpdatingLocation()` immediately replays the last cached fix, which can be minutes old while
    /// still carrying excellent accuracy — so the accuracy filter waves it straight through. Everything
    /// downstream reads a fix's `timestamp` as "now", so age has to be filtered separately.
    @Test(.tags(.edgeCase))
    func aStaleFixIsDroppedEvenWhenItsAccuracyIsPerfect() async {
        let manager = LocationManager()

        await confirmation(expectedCount: 0) { published in
            let subscription = manager.acceptedLocations.sink { _ in published() }
            defer { subscription.cancel() }

            manager.process(makeFix(
                horizontalAccuracy: 1, // pristine
                timestamp: Date(timeIntervalSinceNow: -60) // and a minute out of date
            ))
        }
    }

    /// A stale fix is not a signal-quality problem, so it must not flicker the GPS indicator on its way
    /// to being ignored.
    @Test(.tags(.edgeCase))
    func aStaleFixLeavesTheFixIndicatorAlone() throws {
        let manager = LocationManager()
        manager.process(makeFix(timestamp: Date()))
        try #require(manager.hasFix)

        manager.process(makeFix(timestamp: Date(timeIntervalSinceNow: -60)))

        #expect(manager.hasFix, "a fix we chose to ignore must not report itself as a lost signal")
    }

    // MARK: - Accuracy filter

    @Test(.tags(.edgeCase))
    func anInaccurateFixIsNotPublishedAndDropsTheFixIndicator() async {
        let manager = LocationManager()

        await confirmation(expectedCount: 0) { published in
            let subscription = manager.acceptedLocations.sink { _ in published() }
            defer { subscription.cancel() }

            manager.process(makeFix(horizontalAccuracy: 40, timestamp: Date()))
        }

        #expect(manager.hasFix == false)
        #expect(manager.signalQuality == .poor)
    }

    /// The readouts hold their last trusted value rather than snapping to zero, so a moment of bad signal
    /// reads as "unchanged", not as "you have stopped".
    @Test(.tags(.edgeCase))
    func anInaccurateFixFreezesTheReadoutsRatherThanZeroingThem() {
        let manager = LocationManager()
        manager.process(makeFix(altitude: 150, speed: 8, timestamp: Date()))

        manager.process(makeFix(altitude: 999, horizontalAccuracy: 40, speed: 0, timestamp: Date()))

        expectClose(manager.rawSpeed, 8, within: 0.01)
        #expect(manager.altitude == 150)
    }

    // MARK: - Speed

    /// The bug this deadband exists for: a parked bike doesn't report 0 m/s, it reports a few tenths of
    /// one, and the gauge drew that as a needle creeping to 1–2 km/h and back. A speed smaller than the
    /// fix's own error bar says nothing, so it must read as standing still.
    @Test(.tags(.edgeCase))
    func aSpeedInsideItsOwnErrorBarReadsAsStandingStill() {
        let manager = LocationManager()

        manager.process(makeFix(speed: 0.4, speedAccuracy: 0.5, timestamp: Date()))

        #expect(manager.rawSpeed == 0)
    }

    /// The reason the deadband tracks `speedAccuracy` rather than being one fixed width: indoors and in
    /// street canyons the fix gets noisier and the phantom speed grows with it, and the fix says so.
    @Test(.tags(.edgeCase))
    func aNoisierFixWidensTheDeadbandThatSilencesIt() {
        let manager = LocationManager()

        manager.process(makeFix(speed: 0.9, speedAccuracy: 2, timestamp: Date()))

        #expect(manager.rawSpeed == 0, "a 0.9 m/s reading with a 2 m/s error bar is not movement")
    }

    /// And the reason it's capped: an error bar can be pessimistic enough to swallow a genuine ride, and
    /// a rider actually doing 18 km/h must see 18 km/h no matter how little CoreLocation trusts itself.
    @Test(.tags(.edgeCase))
    func aRealRidingSpeedSurvivesAPessimisticErrorBar() {
        let manager = LocationManager()

        manager.process(makeFix(speed: 5, speedAccuracy: 3, timestamp: Date()))

        expectClose(manager.rawSpeed, 5, within: 0.01)
    }

    /// A negative `speedAccuracy` is CoreLocation's "no idea" sentinel, so the deadband falls back to its
    /// fixed floor — narrow enough that anything above walking pace still registers.
    @Test(.tags(.edgeCase))
    func aFixWithoutASpeedAccuracyFallsBackToTheFixedFloor() {
        let manager = LocationManager()

        manager.process(makeFix(speed: 0.3, speedAccuracy: -1, timestamp: Date()))
        #expect(manager.rawSpeed == 0)

        manager.process(makeFix(speed: 4, speedAccuracy: -1, timestamp: Date()))
        expectClose(manager.rawSpeed, 4, within: 0.01)
    }

    /// CoreLocation's "speed unknown" sentinel is negative, and the deadband subsumes it — anything at or
    /// below the noise floor is a standstill, whether it's noise or an admission of ignorance.
    @Test(.tags(.edgeCase))
    func theUnknownSpeedSentinelReadsAsStandingStill() {
        let manager = LocationManager()

        manager.process(makeFix(speed: -1, timestamp: Date()))

        #expect(manager.rawSpeed == 0)
    }

    /// What the rider actually looks at is the smoothed value, and smoothing a standstill's noise only
    /// spreads it out — the needle has to come to rest at zero and stay there.
    @Test
    func theGaugeSettlesAtZeroWhenTheRiderStops() throws {
        let manager = LocationManager()
        manager.process(makeFix(speed: 8, timestamp: Date()))
        try #require(manager.displaySpeed > 0)

        for _ in 0..<20 {
            manager.process(makeFix(speed: 0.45, speedAccuracy: 0.8, timestamp: Date()))
        }

        expectClose(manager.displaySpeed, 0, within: 0.01, "the needle must rest at zero, not hover")
    }

    // MARK: - Course

    /// GPS course is noise at a standstill, so below ~3.6 km/h it holds its last valid value instead of
    /// spinning the direction arrow.
    @Test(.tags(.edgeCase))
    func courseIsHeldRatherThanUpdatedBelowTheSpeedThreshold() throws {
        let manager = LocationManager()
        manager.process(makeFix(course: 90, speed: 8, timestamp: Date()))
        try #require(manager.course == 90)

        manager.process(makeFix(course: 200, speed: 0.4, timestamp: Date()))

        #expect(manager.course == 90)
    }

    @Test(.tags(.edgeCase))
    func anUnreliableCourseIsIgnored() {
        let manager = LocationManager()
        manager.process(makeFix(course: 90, speed: 8, timestamp: Date()))

        manager.process(makeFix(course: 200, courseAccuracy: 120, speed: 8, timestamp: Date()))

        #expect(manager.course == 90)
    }

    // MARK: - Altitude

    /// A negative vertical accuracy is CoreLocation's "this altitude is meaningless" sentinel.
    @Test(.tags(.edgeCase))
    func altitudeIsIgnoredWhenItsVerticalAccuracyIsInvalid() {
        let manager = LocationManager()
        manager.process(makeFix(altitude: 150, verticalAccuracy: 5, timestamp: Date()))

        manager.process(makeFix(altitude: 999, verticalAccuracy: -1, timestamp: Date()))

        #expect(manager.altitude == 150)
    }
}
