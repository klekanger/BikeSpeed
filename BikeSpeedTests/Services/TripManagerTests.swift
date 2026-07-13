import Testing

@testable import BikeSpeed

/// Pins the behaviour of the trip accumulator as it stands today. Everything that follows in the v2 work
/// writes into `TripManager.consume(_:)`, so this suite is the thing that will notice when one of them
/// breaks a rule that took a season of riding to get right.
@Suite(.tags(.gps))
struct TripManagerTests {

    // MARK: - State machine

    @Test
    func tripStartsIdle() {
        let harness = TripTestHarness()
        #expect(harness.trip.state == .idle)
        #expect(harness.trip.accumulatedDistance == 0)
    }

    @Test
    func startPauseResumeMovesThroughTheStates() {
        let harness = TripTestHarness()

        harness.trip.start()
        #expect(harness.trip.state == .running)

        harness.trip.pause()
        #expect(harness.trip.state == .paused)

        harness.trip.resume()
        #expect(harness.trip.state == .running)
    }

    @Test
    func resetReturnsEverythingToZero() {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()
        harness.move(meters: 50, seconds: 5)
        harness.trip.pause()

        harness.trip.reset()

        #expect(harness.trip.state == .idle)
        #expect(harness.trip.accumulatedDistance == 0)
        #expect(harness.trip.elapsedActiveDuration == 0)
        #expect(harness.trip.maxSpeed == 0)
    }

    /// Reset is only offered from idle or paused; a running trip must not be wiped out from under the rider.
    @Test
    func resetDoesNothingWhileRunning() {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()
        harness.move(meters: 50, seconds: 5)

        harness.trip.reset()

        #expect(harness.trip.state == .running)
        expectClose(harness.trip.accumulatedDistance, 50)
    }

    // MARK: - Distance

    @Test
    func distanceAccumulatesAcrossFixesWhileRunning() {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()

        harness.move(meters: 50, seconds: 5)
        harness.move(meters: 50, seconds: 5)

        expectClose(harness.trip.accumulatedDistance, 100)
    }

    /// Fixes keep arriving when no trip is running — the gauge and compass stay live — but they must not
    /// quietly build up a distance the rider never asked to record.
    @Test
    func distanceDoesNotAccumulateWhileIdle() {
        let harness = TripTestHarness()
        harness.anchor()

        harness.move(meters: 50, seconds: 5)
        harness.move(meters: 50, seconds: 5)

        #expect(harness.trip.accumulatedDistance == 0)
    }

    @Test
    func distanceDoesNotAccumulateWhilePaused() {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()
        harness.move(meters: 50, seconds: 5)

        harness.trip.pause()
        harness.move(meters: 50, seconds: 5)
        harness.move(meters: 50, seconds: 5)

        expectClose(harness.trip.accumulatedDistance, 50)
    }

    /// Resuming must not bank the ground covered while paused: the anchor is kept fresh through the pause,
    /// so the first fix after Resume measures from where the rider actually is.
    @Test
    func resumingDoesNotBankTheDistanceCoveredWhilePaused() {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()
        harness.move(meters: 50, seconds: 5)

        harness.trip.pause()
        harness.move(meters: 1_000, seconds: 60) // wheeled the bike somewhere, or the signal wandered
        harness.trip.resume()

        harness.move(meters: 50, seconds: 5)

        expectClose(harness.trip.accumulatedDistance, 100)
    }

    // MARK: - Jitter floor

    /// A stationary phone's fix wanders by a metre or two. Movement under `max(1 m, 0.5 × accuracy)` is
    /// treated as that wander and contributes nothing, or a bike left at a café would ride a few km.
    @Test(.tags(.edgeCase))
    func movementUnderTheJitterFloorIsIgnored() {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()

        // Floor is max(1, 0.5 × 5) = 2.5 m.
        harness.move(meters: 2, horizontalAccuracy: 5)

        #expect(harness.trip.accumulatedDistance == 0)
    }

    @Test(.tags(.edgeCase))
    func movementAboveTheJitterFloorCounts() {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()

        harness.move(meters: 5, horizontalAccuracy: 5)

        expectClose(harness.trip.accumulatedDistance, 5)
    }

    /// The floor scales with accuracy, so a sloppy fix has to move further before it is believed.
    @Test(.tags(.edgeCase))
    func theJitterFloorScalesWithHorizontalAccuracy() {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()

        // Floor is max(1, 0.5 × 20) = 10 m, so an 8 m step is noise at this accuracy even though it
        // would have counted at a tighter one.
        harness.move(meters: 8, horizontalAccuracy: 20)

        #expect(harness.trip.accumulatedDistance == 0)
    }

    // MARK: - Teleport guard

    @Test(.tags(.edgeCase))
    func aTeleportFixIsRejected() {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()

        // 1 km in one second is 3600 km/h. Not a bike.
        harness.move(meters: 1_000, seconds: 1)

        #expect(harness.trip.accumulatedDistance == 0)
    }

    /// The guard cannot tell which of the two fixes is the artifact, so it assumes the new one is — right
    /// for an isolated spike. But if the *anchor* is the bad fix, every later fix measures implausibly
    /// against it and distance freezes for the rest of the ride. A run of rejections means the anchor is
    /// what's wrong: re-anchor and write off the gap rather than the trip.
    @Test(.tags(.edgeCase))
    func distanceRecoversAfterAStreakOfRejections() {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()

        harness.move(meters: 1_000)
        harness.move(meters: 1_000)
        harness.move(meters: 1_000) // third rejection: the anchor gives up and moves here

        #expect(harness.trip.accumulatedDistance == 0, "the implausible fixes themselves must not count")

        harness.move(meters: 20)

        expectClose(harness.trip.accumulatedDistance, 20, "riding must resume counting from the new anchor")
    }

    // MARK: - Max speed

    @Test
    func maxSpeedTracksThePeakNotTheLatest() {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()

        harness.move(meters: 5, speed: 5)
        harness.move(meters: 12, speed: 12)
        harness.move(meters: 8, speed: 8)

        expectClose(harness.trip.maxSpeed, 12, within: 0.01)
    }

    /// A GPS spike can report an absurd instantaneous speed on an otherwise sane fix. Max speed is clamped
    /// at the same ceiling distance uses, so one bad sample can't leave a 700 km/h "record" in the trip log.
    @Test(.tags(.edgeCase))
    func maxSpeedIsClampedAtThePlausibleCeiling() {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()

        harness.move(meters: 5, speed: 200)

        expectClose(harness.trip.maxSpeed, 120 / 3.6, within: 0.01)
    }

    /// CoreLocation reports "I don't know" as a negative speed, not a slow one.
    @Test(.tags(.edgeCase))
    func anUnknownSpeedSentinelDoesNotDisturbMaxSpeed() {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()

        harness.move(meters: 10, speed: 10)
        harness.move(meters: 5, speed: -1)

        expectClose(harness.trip.maxSpeed, 10, within: 0.01)
    }

    // MARK: - Time and average speed

    @Test
    func elapsedTimeCountsOnlyWhileRunning() {
        let harness = TripTestHarness()
        harness.trip.start()

        harness.clock.advance(10)
        harness.trip.tick()
        expectClose(harness.trip.elapsedActiveDuration, 10, within: 0.01)

        harness.trip.pause()
        harness.clock.advance(60) // sitting in a café
        harness.trip.tick()
        expectClose(harness.trip.elapsedActiveDuration, 10, within: 0.01)

        harness.trip.resume()
        harness.clock.advance(5)
        harness.trip.tick()
        expectClose(harness.trip.elapsedActiveDuration, 15, within: 0.01)
    }

    @Test
    func averageSpeedIsDistanceOverActiveTime() {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()

        harness.move(meters: 100, seconds: 10)

        expectClose(harness.trip.averageSpeed, 10, within: 0.1)
    }

    // MARK: - Auto-pause

    /// GPS speed drifts around a standstill, so the pause has to wait out a debounce rather than firing on
    /// the first slow fix.
    @Test(.tags(.edgeCase))
    func autoPauseWaitsOutTheDebounce() {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()

        harness.move(meters: 0.1, speed: 0.3)
        harness.move(meters: 0.1, speed: 0.3)
        #expect(harness.trip.isAutoPaused == false, "under 3 s below the threshold is not a standstill yet")

        harness.move(meters: 0.1, speed: 0.3)
        harness.move(meters: 0.1, speed: 0.3)
        #expect(harness.trip.isAutoPaused)
    }

    /// The resume threshold sits above the pause threshold on purpose. A single cutoff would flap on and
    /// off as the standstill drift crosses it.
    @Test(.tags(.edgeCase))
    func autoPauseHoldsThroughSpeedsBetweenTheTwoThresholds() {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()
        autoPause(harness)

        harness.move(meters: 0.7, speed: 0.7) // 2.5 km/h: above the pause threshold, below the resume one
        #expect(harness.trip.isAutoPaused, "hysteresis: this must not be read as riding again")

        harness.move(meters: 1, speed: 1.0) // 3.6 km/h: genuinely moving
        #expect(harness.trip.isAutoPaused == false)
    }

    /// Freezing the clock is the whole point: average speed is distance ÷ active time, so counting time at
    /// every red light would drag the average down all ride.
    @Test
    func autoPauseFreezesBothDistanceAndTheClock() {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()
        harness.move(meters: 100, seconds: 10)
        autoPause(harness)

        let distanceAtPause = harness.trip.accumulatedDistance
        let elapsedAtPause = harness.trip.elapsedActiveDuration

        harness.clock.advance(120)
        harness.trip.tick()

        expectClose(harness.trip.accumulatedDistance, distanceAtPause)
        expectClose(harness.trip.elapsedActiveDuration, elapsedAtPause, within: 0.01)
    }

    /// An auto-pause is only ever entered on positive evidence — a fix reporting a standstill — so it has
    /// to be released once that evidence stops arriving. Accuracy often degrades *because* the phone is
    /// still, and a rider who pulled away through a poor-signal stretch would otherwise have that riding
    /// time silently vanish from the trip.
    @Test(.tags(.edgeCase))
    func autoPauseIsReleasedWhenFixesStopArrivingToJustifyIt() {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()
        autoPause(harness)

        harness.clock.advance(6) // no usable fix for longer than the watchdog allows
        harness.trip.tick()

        #expect(harness.trip.isAutoPaused == false)
        #expect(harness.trip.state == .running)
    }

    /// A manual pause supersedes an auto-pause. Rolling forward must never resume a trip the rider
    /// deliberately stopped.
    @Test(.tags(.edgeCase))
    func movingAgainDoesNotResumeAManuallyPausedTrip() {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()
        harness.trip.pause()

        harness.move(meters: 20, speed: 8)

        #expect(harness.trip.state == .paused)
        #expect(harness.trip.accumulatedDistance == 0)
    }

    @Test
    func autoPauseNeverEngagesWhenTheSettingIsOff() {
        let harness = TripTestHarness(autoPauseEnabled: false)
        harness.anchor()
        harness.trip.start()

        autoPause(harness)

        #expect(harness.trip.isAutoPaused == false)
    }

    @Test
    func turningTheSettingOffReleasesAnActiveAutoPause() throws {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()
        autoPause(harness)
        try #require(harness.trip.isAutoPaused)

        harness.settings.autoPauseEnabled = false

        #expect(harness.trip.isAutoPaused == false)
    }

    // MARK: - Saving

    @Test
    func aRunningTripCannotBeSaved() {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()
        harness.move(meters: 100, seconds: 10)

        #expect(harness.trip.canSaveTrip == false)
        #expect(harness.trip.makeLogEntry() == nil)
    }

    /// An auto-pause is a flag on `.running`, not a `TripState` case, precisely so the Save button does not
    /// light up at every red light.
    @Test(.tags(.edgeCase))
    func anAutoPausedTripCannotBeSaved() {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()
        harness.move(meters: 100, seconds: 10)
        autoPause(harness)

        #expect(harness.trip.isAutoPaused)
        #expect(harness.trip.canSaveTrip == false)
    }

    @Test(arguments: [
        (distance: 5.0, seconds: 10.0),  // far enough? no — under the 10 m floor
        (distance: 100.0, seconds: 4.0), // long enough? no — under the 5 s floor
    ])
    func aTripTooSmallToBeMeaningfulCannotBeSaved(trip: (distance: Double, seconds: Double)) {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()
        harness.move(meters: trip.distance, seconds: trip.seconds)
        harness.trip.pause()

        #expect(harness.trip.canSaveTrip == false)
        #expect(harness.trip.makeLogEntry() == nil)
    }

    @Test
    func aPausedTripOfSubstanceCanBeSaved() throws {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()
        harness.move(meters: 100, seconds: 10)
        harness.trip.pause()

        #expect(harness.trip.canSaveTrip)

        let entry = try #require(harness.trip.makeLogEntry())
        expectClose(entry.distance, 100)
        expectClose(entry.duration, 10, within: 0.01)
        expectClose(entry.averageSpeed, 10, within: 0.1)
    }

    // MARK: - Helpers

    /// Rides the trip into an auto-pause: four fixes below the pause threshold, spanning more than the
    /// debounce.
    private func autoPause(_ harness: TripTestHarness) {
        for _ in 0..<4 {
            harness.move(meters: 0.1, speed: 0.3)
        }
    }
}
