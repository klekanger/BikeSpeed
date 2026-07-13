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
    func aGoodFixIsAcceptedAndPublished() throws {
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
    func aStaleFixLeavesTheFixIndicatorAlone() {
        let manager = LocationManager()
        manager.process(makeFix(timestamp: Date()))
        try? #require(manager.hasFix)

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

    // MARK: - Course

    /// GPS course is noise at a standstill, so below ~3.6 km/h it holds its last valid value instead of
    /// spinning the direction arrow.
    @Test(.tags(.edgeCase))
    func courseIsHeldRatherThanUpdatedBelowTheSpeedThreshold() {
        let manager = LocationManager()
        manager.process(makeFix(course: 90, speed: 8, timestamp: Date()))
        try? #require(manager.course == 90)

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

    // MARK: - Signal quality

    @Test(arguments: zip(
        [5.0, 10.0, 11.0, 30.0, 31.0, -1.0],
        [GPSSignalQuality.good, .good, .fair, .fair, .poor, .poor]
    ))
    func signalQualityBucketsHorizontalAccuracy(accuracy: CLLocationAccuracy, expected: GPSSignalQuality) {
        let quality = GPSSignalQuality(horizontalAccuracy: accuracy, goodWithin: 10, acceptableWithin: 30)
        #expect(quality == expected)
    }

    @Test
    func onlyPoorSignalIsUnusable() {
        #expect(GPSSignalQuality.good.isUsable)
        #expect(GPSSignalQuality.fair.isUsable)
        #expect(GPSSignalQuality.poor.isUsable == false)
    }
}
