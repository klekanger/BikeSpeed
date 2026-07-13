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

    // MARK: - Background recording

    /// GPS in the background costs battery, so it's held exactly for the span of a recording: on while
    /// the trip is running, off the moment it isn't. Asserted against the fake's recorded state — the
    /// behaviour is "TripManager asked for it", never how CoreLocation honours the ask.

    @Test
    func backgroundUpdatesAreHeldExactlyWhileTheTripRecords() {
        let harness = TripTestHarness()
        #expect(harness.locationSource.backgroundUpdatesEnabled == false, "merely constructing a trip must not hold GPS awake")

        harness.trip.start()
        #expect(harness.locationSource.backgroundUpdatesEnabled)

        harness.trip.pause()
        #expect(harness.locationSource.backgroundUpdatesEnabled == false)

        harness.trip.resume()
        #expect(harness.locationSource.backgroundUpdatesEnabled)
    }

    @Test
    func resettingATripReleasesBackgroundUpdates() {
        let harness = TripTestHarness()
        harness.trip.start()
        harness.trip.pause()

        harness.trip.reset()

        #expect(harness.locationSource.backgroundUpdatesEnabled == false)
    }

    /// Fixes flow whenever the app is open — the gauge is live from launch — but a trip nobody started
    /// must not be the thing keeping GPS running under a locked screen.
    @Test
    func fixesArrivingWithoutATripDoNotRequestBackgroundUpdates() {
        let harness = TripTestHarness()
        harness.anchor()

        harness.move(meters: 50, seconds: 5)

        #expect(harness.locationSource.backgroundUpdatesEnabled == false)
    }

    /// An auto-pause is still a recording: the only way out of it is a fix above the resume threshold,
    /// and with the phone locked at a red light that fix can only arrive if GPS stays on. Releasing
    /// background updates here would freeze the trip at the first light after the screen locks.
    @Test(.tags(.edgeCase))
    func anAutoPauseDoesNotReleaseBackgroundUpdates() {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()

        autoPause(harness)

        #expect(harness.trip.isAutoPaused)
        #expect(harness.locationSource.backgroundUpdatesEnabled)
    }

    // MARK: - Elevation

    /// Elevation rides the GPS funnel — sampled at each accepted fix — so ascent and grade inherit the
    /// same running/auto-pause gating that already guards distance. The harness has no barometer unless
    /// a test asks for one, so the plain cases exercise the GPS-altitude fallback.

    @Test
    func ascentAccumulatesFromGPSAltitudeWhileRiding() throws {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()

        harness.move(meters: 20, seconds: 2, altitude: 100) // baseline sample
        for step in 1...10 {
            harness.move(meters: 20, seconds: 2, altitude: 100 + Double(step) * 5)
        }

        expectClose(try #require(harness.trip.totalAscent), 50)
        #expect(harness.trip.totalDescent == 0)
    }

    @Test
    func descentIsRecordedAlongsideAscent() throws {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()

        harness.move(meters: 20, seconds: 2, altitude: 100)
        for step in 1...4 {
            harness.move(meters: 20, seconds: 2, altitude: 100 + Double(step) * 5) // up 20
        }
        for step in 1...6 {
            harness.move(meters: 20, seconds: 2, altitude: 120 - Double(step) * 5) // down 30
        }

        expectClose(try #require(harness.trip.totalAscent), 20)
        expectClose(try #require(harness.trip.totalDescent), 30)
    }

    /// GPS altitude wobbles by metres at constant true height; the fallback's wider deadband exists so
    /// that wobble never turns into a phantom climb.
    @Test(.tags(.edgeCase))
    func gpsAltitudeNoiseUnderTheDeadbandAddsNoAscent() {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()

        for step in 0..<20 {
            harness.move(meters: 20, seconds: 2, altitude: 100 + (step.isMultiple(of: 2) ? 0 : 2))
        }

        #expect(harness.trip.totalAscent == 0)
        #expect(harness.trip.totalDescent == 0)
    }

    @Test
    func theBarometerIsPreferredOverGPSAltitudeWhenAvailable() throws {
        let harness = TripTestHarness(barometerAvailable: true)
        harness.anchor()
        harness.trip.start()

        harness.altimeter.relativeAltitude = 0
        harness.move(meters: 20, seconds: 2, altitude: 500) // GPS altitude is wild — it must be ignored
        harness.altimeter.relativeAltitude = 4
        harness.move(meters: 20, seconds: 2, altitude: 700)

        expectClose(try #require(harness.trip.totalAscent), 4, within: 0.001)
    }

    @Test
    func elevationDoesNotAccumulateWithoutARunningTrip() {
        let harness = TripTestHarness()
        harness.anchor()

        harness.move(meters: 20, seconds: 2, altitude: 150)
        harness.move(meters: 20, seconds: 2, altitude: 200)

        #expect(harness.trip.totalAscent == nil, "no trip has sampled anything, so there is no figure at all")
        #expect(harness.trip.currentGrade == nil)
    }

    @Test
    func elevationFreezesDuringAManualPause() throws {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()
        harness.move(meters: 20, seconds: 2, altitude: 100)
        harness.move(meters: 20, seconds: 2, altitude: 110)
        harness.trip.pause()

        harness.move(meters: 20, seconds: 2, altitude: 200)

        expectClose(try #require(harness.trip.totalAscent), 10)
    }

    /// Barometric pressure drifts with the weather, which reads as altitude change while the bike sits
    /// still. Auto-pause stops elevation sampling exactly as it stops distance, so a long red light in a
    /// building weather front adds no climb.
    @Test(.tags(.edgeCase))
    func barometricDriftDuringAnAutoPauseAddsNoAscent() throws {
        let harness = TripTestHarness(barometerAvailable: true)
        harness.anchor()
        harness.trip.start()
        harness.altimeter.relativeAltitude = 0
        harness.move(meters: 20, seconds: 2)
        autoPause(harness)
        try #require(harness.trip.isAutoPaused)

        harness.altimeter.relativeAltitude = 6 // pressure drift at the kerb
        harness.move(meters: 0.1, speed: 0.3) // still standing; the fix must not sample the drift

        #expect(harness.trip.isAutoPaused)
        #expect(harness.trip.totalAscent == 0)
    }

    @Test
    func gradeReadsTheCurrentClimbOnceItsWindowFills() throws {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()

        harness.move(meters: 10, seconds: 1, altitude: 100)
        #expect(harness.trip.currentGrade == nil, "no grade before the window's worth of riding")

        for step in 1...5 {
            harness.move(meters: 10, seconds: 1, altitude: 100 + Double(step) * 0.5) // 5 %
        }

        expectClose(try #require(harness.trip.currentGrade), 0.05, within: 0.005)
    }

    @Test
    func resetClearsElevationAndGrade() {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()
        harness.move(meters: 20, seconds: 2, altitude: 100)
        for step in 1...5 {
            harness.move(meters: 20, seconds: 2, altitude: 100 + Double(step) * 5)
        }
        harness.trip.pause()

        harness.trip.reset()

        #expect(harness.trip.totalAscent == nil)
        #expect(harness.trip.totalDescent == nil)
        #expect(harness.trip.currentGrade == nil)
    }

    @Test
    func theLogEntryCarriesAscentAndDescent() throws {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()
        harness.move(meters: 20, seconds: 2, altitude: 100)
        for step in 1...4 {
            harness.move(meters: 20, seconds: 2, altitude: 100 + Double(step) * 5)
        }
        harness.trip.pause()

        let entry = try #require(harness.trip.makeLogEntry())

        expectClose(try #require(entry.totalAscent), 20)
        expectClose(try #require(entry.totalDescent), 0, within: 0.001)
    }

    /// Nil, not zero: a trip whose fixes never carried a usable altitude has no answer to "how much did
    /// you climb", and writing 0 would be indistinguishable from a genuinely flat ride.
    @Test(.tags(.edgeCase))
    func aTripWithoutAltitudeDataSavesNilRatherThanZero() throws {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()
        harness.move(meters: 100, seconds: 10, verticalAccuracy: -1)
        harness.trip.pause()

        let entry = try #require(harness.trip.makeLogEntry())

        #expect(entry.totalAscent == nil)
        #expect(entry.totalDescent == nil)
    }

    // MARK: - Elevation source

    /// `CMAltimeter.isRelativeAltitudeAvailable()` reports hardware, not authorization: a user who
    /// denies the Motion & Fitness prompt has an "available" barometer that never delivers a reading.
    /// `AltimeterManager` folds that failure into `isAvailable`, and the trip must then ride the GPS
    /// altitude every accepted fix already carries instead of recording nothing forever.
    @Test(.tags(.edgeCase))
    func aFailedBarometerFallsBackToGPSAltitude() throws {
        let harness = TripTestHarness(barometerAvailable: true)
        harness.anchor()
        harness.trip.start()

        harness.altimeter.isAvailable = false // what AltimeterManager reports once updates error

        harness.move(meters: 20, seconds: 2, altitude: 100)
        for step in 1...4 {
            harness.move(meters: 20, seconds: 2, altitude: 100 + Double(step) * 5)
        }

        expectClose(try #require(harness.trip.totalAscent), 20)
    }

    /// The barometer needs a moment to deliver its first reading after starting. The trip waits a
    /// short grace rather than latching GPS on the very first fix — but a barometer that stays
    /// silent (permission denied without an error surfacing) must not starve the trip past it.
    @Test(.tags(.edgeCase))
    func aSilentBarometerYieldsToGPSAltitudeAfterAGrace() throws {
        let harness = TripTestHarness(barometerAvailable: true)
        harness.anchor()
        harness.trip.start()

        // isAvailable stays true and relativeAltitude stays nil: the pathological silent barometer.
        for step in 0..<5 {
            harness.move(meters: 20, seconds: 2, altitude: 100 + Double(step) * 5)
        }
        #expect(harness.trip.totalAscent == nil, "still inside the grace, waiting on the barometer")

        for step in 5..<14 {
            harness.move(meters: 20, seconds: 2, altitude: 100 + Double(step) * 5)
        }

        let ascent = try #require(harness.trip.totalAscent, "past the grace, GPS altitude must be flowing")
        #expect(ascent > 0)
    }

    /// Barometric and GPS altitude measure against different zero points, so switching source
    /// mid-trip would bank the difference between them as a phantom climb. Once latched, a trip
    /// stays on its source: a barometer that dies mid-ride stops the figures rather than corrupting them.
    @Test(.tags(.edgeCase))
    func theElevationSourceStaysLatchedForTheWholeTrip() throws {
        let harness = TripTestHarness(barometerAvailable: true)
        harness.anchor()
        harness.trip.start()
        harness.altimeter.relativeAltitude = 0
        harness.move(meters: 20, seconds: 2)
        harness.altimeter.relativeAltitude = 4
        harness.move(meters: 20, seconds: 2)
        expectClose(try #require(harness.trip.totalAscent), 4, within: 0.001)

        harness.altimeter.isAvailable = false // barometer dies mid-trip
        harness.altimeter.relativeAltitude = nil
        for step in 1...4 {
            harness.move(meters: 20, seconds: 2, altitude: 300 + Double(step) * 10) // GPS climbing hard
        }

        expectClose(try #require(harness.trip.totalAscent), 4, within: 0.001,
                    "GPS altitude must not be spliced onto a barometer baseline")
    }

    // MARK: - Elevation across pauses

    /// Barometric pressure drifts with the weather while the bike sits parked. Gating the sampling
    /// is only half the protection: the accumulator's reference point must not survive the pause
    /// either, or the whole drift lands as one phantom climb on the first fix after resuming.
    @Test(.tags(.edgeCase))
    func pauseDriftIsNotBankedOnResume() throws {
        let harness = TripTestHarness(barometerAvailable: true)
        harness.anchor()
        harness.trip.start()
        harness.altimeter.relativeAltitude = 0
        harness.move(meters: 20, seconds: 2)
        harness.altimeter.relativeAltitude = 2
        harness.move(meters: 20, seconds: 2)
        expectClose(try #require(harness.trip.totalAscent), 2, within: 0.001)

        harness.trip.pause()
        harness.clock.advance(1800) // half an hour at the café while a weather front moves through
        harness.trip.resume()
        harness.altimeter.relativeAltitude = 8 // the restarted barometer reads the drift

        harness.move(meters: 20, seconds: 2)
        harness.move(meters: 20, seconds: 2)
        expectClose(try #require(harness.trip.totalAscent), 2, within: 0.001,
                    "the drift across the pause must anchor fresh, not count as climb")

        harness.altimeter.relativeAltitude = 11 // then a real climb after the stop
        harness.move(meters: 20, seconds: 2)
        expectClose(try #require(harness.trip.totalAscent), 5, within: 0.001)
    }

    /// The same protection for an auto-pause: fixes keep arriving throughout, so the resume is just
    /// another accepted fix — the gap in *sampling* is what must trigger the re-baseline.
    @Test(.tags(.edgeCase))
    func autoPauseDriftIsNotBankedOnResume() throws {
        let harness = TripTestHarness(barometerAvailable: true)
        harness.anchor()
        harness.trip.start()
        harness.altimeter.relativeAltitude = 0
        harness.move(meters: 20, seconds: 2)
        harness.move(meters: 20, seconds: 2)
        autoPause(harness)
        try #require(harness.trip.isAutoPaused)

        for _ in 0..<5 {
            harness.move(meters: 0.1, seconds: 5, speed: 0.3) // 25 s standing at the light
        }
        harness.altimeter.relativeAltitude = 6 // pressure drift at the kerb

        harness.move(meters: 5, seconds: 1) // pulling away releases the auto-pause
        try #require(harness.trip.isAutoPaused == false)
        harness.move(meters: 20, seconds: 2)
        #expect(harness.trip.totalAscent == 0, "the drift accumulated while paused must not be banked")

        harness.altimeter.relativeAltitude = 8
        harness.move(meters: 20, seconds: 2)
        expectClose(try #require(harness.trip.totalAscent), 2, within: 0.001)
    }

    /// The grade window must not span a pause either: rise measured across a stop is not a slope the
    /// rider is on, so the window starts empty and reads nil until a fresh 30 m has been ridden.
    @Test(.tags(.edgeCase))
    func theGradeWindowDoesNotSpanAPause() throws {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()
        for step in 0..<6 {
            harness.move(meters: 10, seconds: 1, altitude: 100 + Double(step) * 0.5) // 5 %
        }
        try #require(harness.trip.currentGrade != nil)

        harness.trip.pause()
        harness.clock.advance(600)
        harness.trip.resume()
        harness.move(meters: 10, seconds: 1, altitude: 110)

        #expect(harness.trip.currentGrade == nil,
                "a slope measured across the pause would be a fiction — the window must refill first")
    }

    /// The gradient caption claims a live reading, so it must not keep asserting the last hill while
    /// the bike stands still — unlike `course`, which is deliberately sticky, a grade is a statement
    /// about *now*.
    @Test
    func theGradeReadoutClearsWhenTheTripStopsBeingRidden() throws {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()
        for step in 0..<6 {
            harness.move(meters: 10, seconds: 1, altitude: 100 + Double(step) * 0.5)
        }
        try #require(harness.trip.currentGrade != nil)

        autoPause(harness)
        try #require(harness.trip.isAutoPaused)
        #expect(harness.trip.currentGrade == nil, "auto-paused at the crest, the panel must not still read a climb")

        harness.move(meters: 5, seconds: 1) // resume
        for step in 0..<6 {
            harness.move(meters: 10, seconds: 1, altitude: 103 + Double(step) * 0.5)
        }
        try #require(harness.trip.currentGrade != nil, "riding again refills the window")

        harness.trip.pause()
        #expect(harness.trip.currentGrade == nil)
    }

    // MARK: - Elevation at a standstill

    /// With auto-pause switched off, nothing else stops fixes from flowing at a standstill. Distance
    /// is protected by the jitter floor; elevation must be gated the same way, or GPS altitude
    /// wandering at a red light accrues as climb while the bike never moves.
    @Test(.tags(.edgeCase))
    func aStandstillWithAutoPauseDisabledAddsNoAscent() throws {
        let harness = TripTestHarness(autoPauseEnabled: false)
        harness.anchor()
        harness.trip.start()
        harness.move(meters: 20, seconds: 2, altitude: 100)
        harness.move(meters: 20, seconds: 2, altitude: 100)

        for step in 0..<30 { // a long light, GPS altitude wandering ±4.5 m beyond the 3 m deadband
            harness.move(meters: 0.1, seconds: 1, speed: 0,
                         altitude: 100 + (step.isMultiple(of: 2) ? 4.5 : -4.5))
        }

        #expect(harness.trip.totalAscent == 0)
        #expect(harness.trip.totalDescent == 0)
    }

    /// GPS vertical accuracy of 20–30 m against a 3 m deadband would manufacture hundreds of phantom
    /// metres in an urban canyon. A fix whose altitude error bar dwarfs the deadband contributes nothing.
    @Test(.tags(.edgeCase))
    func poorVerticalAccuracyDoesNotFeedTheClimb() throws {
        let harness = TripTestHarness()
        harness.anchor()
        harness.trip.start()

        for step in 0..<5 {
            harness.move(meters: 20, seconds: 2, altitude: 100 + Double(step) * 5, verticalAccuracy: 40)
        }
        #expect(harness.trip.totalAscent == nil, "an error bar wider than the climb is not data")

        harness.move(meters: 20, seconds: 2, altitude: 130, verticalAccuracy: 5)
        for step in 1...4 {
            harness.move(meters: 20, seconds: 2, altitude: 130 + Double(step) * 5, verticalAccuracy: 5)
        }
        expectClose(try #require(harness.trip.totalAscent), 20)
    }

    // MARK: - Barometer lifecycle

    /// The barometer runs for exactly the span of a recording, like background location updates: the
    /// Motion permission prompt then belongs to the first trip, not to app launch, and the sensor
    /// isn't held hot while the app sits idle.
    @Test
    func barometerUpdatesFollowTheTripLifecycle() {
        let harness = TripTestHarness(barometerAvailable: true)
        harness.anchor()
        #expect(harness.altimeter.isUpdating == false)

        harness.trip.start()
        #expect(harness.altimeter.isUpdating)

        harness.trip.pause()
        #expect(harness.altimeter.isUpdating == false)

        harness.trip.resume()
        #expect(harness.altimeter.isUpdating)

        harness.trip.pause()
        harness.trip.reset()
        #expect(harness.altimeter.isUpdating == false)
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
