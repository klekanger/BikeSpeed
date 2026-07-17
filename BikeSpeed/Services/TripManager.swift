import Combine
import CoreLocation
import Foundation
import Observation

/// Owns the Start/Pause/Reset trip state machine and the distance/average-speed accumulation
/// derived from accepted location fixes. Elapsed active time is wall-clock based so it stays
/// correct across app backgrounding.
@MainActor
@Observable
final class TripManager {
    private(set) var state: TripState = .idle
    private(set) var accumulatedDistance: CLLocationDistance = 0 // meters
    private(set) var elapsedActiveDuration: TimeInterval = 0
    private(set) var maxSpeed: CLLocationSpeed = 0 // m/s, instantaneous

    /// Nil until any usable altitude has been sampled: "no data" must stay distinguishable from "a
    /// flat ride" in the live UI just as it is in the saved log (see `TripLogEntry`).
    private(set) var totalAscent: CLLocationDistance? // meters
    private(set) var totalDescent: CLLocationDistance? // meters, positive
    /// Rise over a trailing ~30 m of run — e.g. 0.05 for a 5 % climb. Nil until enough of the trip
    /// has been ridden to measure one honestly; see `GradeCalculator`.
    private(set) var currentGrade: Double?

    /// A running trip stopped accumulating because the rider is standing still. Deliberately a flag on
    /// `.running`, not a `TripState` case: a manual pause must stay distinguishable from an auto-pause
    /// (else rolling forward resumes a deliberately-paused trip), and `canSaveTrip` must not light up
    /// at every red light.
    private(set) var isAutoPaused = false

    private var accumulatedActiveDuration: TimeInterval = 0
    private var activeStart: Date?
    private var previousLocation: CLLocation?
    /// Background location updates run for exactly the span of a recording — on at `start()`/`resume()`,
    /// off at `pause()`/`reset()`. An auto-pause deliberately keeps them: its only exit is a fix above
    /// the resume threshold, which can never arrive under a locked screen once GPS is released.
    private let locationSource: any LocationSource
    @ObservationIgnored private var cancellable: AnyCancellable?
    /// The wall clock, injected. Everything asking "what time is it now" (as opposed to reading a fix's
    /// own `timestamp`) goes through this, so tests drive elapsed time and the auto-pause watchdog
    /// without sleeping.
    private let now: @MainActor () -> Date
    /// Read directly wherever auto-pause is decided rather than mirrored off a subscription: under
    /// `@Observable` there is no `$autoPauseEnabled` publisher, and a plain read always sees the current
    /// value anyway. See `tick()` for the one case a read alone doesn't cover.
    private let settings: SettingsStore
    @ObservationIgnored private var tickTimer: Timer?

    /// Set once in `start()` and never touched by `resume()`, unlike `activeStart` — this is the
    /// stable wall-clock start time saved into a `TripLogEntry`.
    private var tripStartDate: Date?
    /// The trip's height profile, for the saved trip's elevation chart. `@ObservationIgnored` and read once
    /// at Save, for the same reason as `routeSamples` below: nothing draws it live.
    @ObservationIgnored private(set) var altitudeProfile: [AltitudeSample] = []
    private var lastAltitudeSampleDistance: CLLocationDistance = 0
    private let altitudeSampleDistanceInterval: CLLocationDistance = 25 // meters

    /// The trip's recorded track, for the detail map and GPX export. Decimated by distance like
    /// `altitudeProfile` but far more finely: a track sampled every 25 m visibly cuts corners on a map.
    /// `@ObservationIgnored` — nothing draws it live, and waking observers for a growing array would
    /// invalidate the gauge for no benefit; `TripControlBar` reads it once, at Save.
    @ObservationIgnored private(set) var routeSamples: [RouteSample] = []
    private var lastRouteSampleDistance: CLLocationDistance = 0
    private let routeSampleDistanceInterval: CLLocationDistance = 10 // meters

    /// The barometer. Ascent/descent and grade are *sampled* from it at each accepted fix that advanced
    /// distance, not accumulated on their own subscription, so they inherit `consume(_:)`'s running and
    /// auto-pause gating — and a standstill, where pressure drift and GPS altitude wander read as climb,
    /// samples nothing.
    private let altimeter: any AltitudeSource
    /// The altitude source this trip is committed to, latched once from data actually arriving (see
    /// `latchElevationSource(for:)`): hardware presence can't decide — a barometer with denied Motion &
    /// Fitness permission reports available yet never delivers — and the two sources measure against
    /// different zero points, so switching mid-trip would bank the difference as phantom climb.
    private enum ElevationSource { case undecided, barometer, gps }
    private var elevationSource: ElevationSource = .undecided
    /// Starts on the GPS deadband as a placeholder; the latch replaces it with an accumulator sized
    /// to the source that actually won.
    private var elevation = ElevationAccumulator(deadband: TripManager.gpsAltitudeDeadband)
    private var grade = GradeCalculator(windowDistance: 30)
    private var lastElevationSampleTimestamp: Date?
    private var barometerGraceFixesRemaining = TripManager.barometerLatchGraceFixes
    /// Deadbands per altitude source: the barometer resolves to ~±1 m; the GPS fallback (used where
    /// there is no barometer, notably the Simulator) wobbles by metres and needs the wider band.
    private static let barometerDeadband: CLLocationDistance = 1
    private static let gpsAltitudeDeadband: CLLocationDistance = 3
    /// Beyond this, GPS altitude's own error bar manufactures climb — a 30 m error against a 3 m
    /// deadband — so such fixes contribute nothing.
    private static let maxAltitudeVerticalAccuracy: CLLocationAccuracy = 15
    /// How many fixes an undecided trip waits for the just-started barometer's first reading before
    /// settling for GPS. Readings normally arrive within a second or two, and denied permission flips
    /// `isAvailable` instead, so this only decides the pathological silent case.
    private static let barometerLatchGraceFixes = 10
    /// A sampling gap longer than this — a pause, standstill, or stretch of unusable fixes — separates
    /// two readings that aren't comparable: whatever altitude did in between wasn't ridden, so the next
    /// sample re-baselines instead of banking the gap (see `sampleElevation`).
    private static let elevationContinuityGap: TimeInterval = 15

    /// Guards against GPS teleport artifacts corrupting the trip total.
    private let maxPlausibleSpeed: CLLocationSpeed = 120 / 3.6 // ~120 km/h in m/s
    private let jitterFloor: CLLocationDistance = 1.0
    /// How many implausible fixes in a row to reject before concluding the anchor is the bad one. The
    /// guard can't tell which of the two locations is the artifact, so it blames the new fix — correct
    /// for an isolated spike. But if `previousLocation` is the outlier, every later fix measures an
    /// implausible speed against it and is dropped, and a dropped fix doesn't advance the anchor, so
    /// distance would freeze for the rest of the ride (only Reset clears it). A genuine spike is a
    /// single fix, so a streak means the anchor is wrong: re-anchor and write off the gap, costing at
    /// most this many fixes instead of the whole trip.
    private let maxTeleportRejections = 3
    private var teleportRejections = 0

    /// Auto-pause thresholds. Resume sits above pause (hysteresis): GPS speed drifts around 0–1.5 km/h
    /// at a standstill, so a single cutoff would flap. Pausing waits out `autoPauseDelay`; resuming is
    /// immediate, so no moving time or distance is lost pulling away from a light.
    private let autoPauseSpeed: CLLocationSpeed = 2 / 3.6 // 2 km/h in m/s
    private let autoResumeSpeed: CLLocationSpeed = 3 / 3.6 // 3 km/h in m/s
    private let autoPauseDelay: TimeInterval = 3
    /// How long an auto-pause may survive with no accepted fix to justify it. Fixes arrive about once a
    /// second (`kCLDistanceFilterNone`), so this gap means the signal went unusable, not that the rider
    /// is holding still. See `releaseAutoPauseIfUnconfirmed()`.
    private let autoPauseFixTimeout: TimeInterval = 5
    private var belowThresholdSince: Date?
    private var lastAcceptedFix: Date?

    var averageSpeed: Double { // m/s
        let duration = currentElapsedActiveDuration()
        guard duration > 0 else { return 0 }
        return accumulatedDistance / duration
    }

    /// Whether `makeLogEntry()` would currently succeed — gates the Save button so it's enabled only
    /// when there's something meaningful to save.
    var canSaveTrip: Bool {
        state == .paused && accumulatedActiveDuration >= 5 && accumulatedDistance >= 10
    }

    /// Whether `reset()` would clear anything — gates the Reset button. Resettable exactly while
    /// manually paused: mid-ride (including auto-pause) it must not be wiped from under the rider, and
    /// an idle trip is already at zero. No distance/duration floor, unlike `canSaveTrip`: clearing a
    /// false start too short to save is precisely what Reset is for.
    var canResetTrip: Bool {
        state == .paused
    }

    init(
        locationManager: any LocationSource,
        altimeter: any AltitudeSource,
        settings: SettingsStore,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.locationSource = locationManager
        self.altimeter = altimeter
        self.settings = settings
        self.now = now
        cancellable = locationManager.acceptedLocations.sink { [weak self] location in
            self?.consume(location)
        }
        // Scheduled from the main actor, so the block fires on the main run loop; asserting that
        // isolation keeps `tick()` synchronous instead of hopping through a `Task`.
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    /// The periodic work the trip clock drives: retire an unconfirmed auto-pause and republish elapsed
    /// time so a running trip's duration ticks up between fixes. Split from the timer so tests drive it
    /// directly rather than waiting on it.
    func tick() {
        // Switching auto-pause off must release one already active, and the clock is the only place that
        // can see it: `updateAutoPause(for:)` reads the setting too but runs on accepted fixes, and an
        // auto-paused rider is standing still, so there may be no next fix. This is what the old
        // `settings.$autoPauseEnabled` sink did; at 0.5 s a toggle still feels instant.
        if !settings.autoPauseEnabled { clearAutoPause() }
        releaseAutoPauseIfUnconfirmed()
        guard activeStart != nil else { return }
        elapsedActiveDuration = currentElapsedActiveDuration()
    }

    func start() {
        guard state == .idle else { return }
        state = .running
        startClock()
        tripStartDate = now()
        locationSource.setBackgroundUpdates(true)
        altimeter.startUpdates()
    }

    func pause() {
        guard state == .running else { return }
        // Set before `clearAutoPause()` so it sees `.paused` and doesn't restart the clock: a manual
        // pause supersedes an auto-pause, and releasing it is now the user's call.
        state = .paused
        suspendClock()
        clearAutoPause()
        locationSource.setBackgroundUpdates(false)
        altimeter.stopUpdates()
        // A parked bike isn't on a slope; otherwise the readout asserts the last hill for the whole pause.
        currentGrade = nil
    }

    func resume() {
        guard state == .paused else { return }
        startClock()
        state = .running
        locationSource.setBackgroundUpdates(true)
        altimeter.startUpdates()
        // Altitude across the pause wasn't ridden, and the restarted barometer rebases its zero anyway,
        // so re-baseline rather than bank the difference as climb. (The sampling-gap rule in
        // `sampleElevation` catches this too, but a short pause with a rebased barometer would slip under it.)
        elevation.reanchor()
        grade.reset()
    }

    func reset() {
        guard state == .idle || state == .paused else { return }
        accumulatedDistance = 0
        accumulatedActiveDuration = 0
        elapsedActiveDuration = 0
        maxSpeed = 0
        activeStart = nil
        previousLocation = nil
        teleportRejections = 0
        tripStartDate = nil
        clearAutoPause() // safe here: `state` is never `.running`, so this can't start the clock
        lastAcceptedFix = nil
        altitudeProfile.removeAll()
        lastAltitudeSampleDistance = 0
        routeSamples.removeAll()
        lastRouteSampleDistance = 0
        elevation.reset()
        grade.reset()
        totalAscent = nil
        totalDescent = nil
        currentGrade = nil
        elevationSource = .undecided
        barometerGraceFixesRemaining = Self.barometerLatchGraceFixes
        lastElevationSampleTimestamp = nil
        state = .idle
        locationSource.setBackgroundUpdates(false)
        altimeter.stopUpdates()
    }

    /// Snapshots the current trip into a saveable log entry, or `nil` if there's no paused trip or it's
    /// too short/short-lived to be meaningful.
    ///
    /// The entry is the trip's *scalars* only; its height profile and track are separate payloads
    /// (`altitudeProfile`, `routeSamples`) the caller passes to `TripDataStack.save` alongside this. See
    /// `TripLogEntry` for why they aren't in it.
    func makeLogEntry() -> TripLogEntry? {
        guard state == .paused, let tripStartDate else { return nil }
        guard accumulatedActiveDuration >= 5, accumulatedDistance >= 10 else { return nil }
        return TripLogEntry(
            id: UUID(),
            startDate: tripStartDate,
            duration: accumulatedActiveDuration,
            distance: accumulatedDistance,
            averageSpeed: averageSpeed,
            maxSpeed: maxSpeed,
            // Already nil when no fix ever carried a usable altitude: "we don't know" must stay
            // distinguishable from "it was flat". See `TripLogEntry`.
            totalAscent: totalAscent,
            totalDescent: totalDescent
        )
    }

    /// `activeStart` is non-nil exactly while the clock runs — not idle, not manually or auto-paused —
    /// so these two are the only places the wall-clock total is folded up, shared by both pauses.
    private func startClock() {
        activeStart = now()
    }

    private func suspendClock() {
        guard let activeStart else { return } // already stopped; folding again would double-count
        accumulatedActiveDuration += now().timeIntervalSince(activeStart)
        self.activeStart = nil
        elapsedActiveDuration = accumulatedActiveDuration
    }

    private func currentElapsedActiveDuration() -> TimeInterval {
        accumulatedActiveDuration + (activeStart.map { now().timeIntervalSince($0) } ?? 0)
    }

    private func beginAutoPause() {
        isAutoPaused = true
        suspendClock()
        // Standing still: no current slope, else the readout keeps asserting the last hill.
        currentGrade = nil
    }

    /// The one place auto-pause is unwound. It is two pieces of state — the `isAutoPaused` flag and the
    /// `belowThresholdSince` debounce that arms it — and every exit clears both here: manual pause,
    /// reset, setting off, a resume-speed fix, the fix-loss watchdog, and moving again. Owning both
    /// together is the point: they were previously cleared in five places that didn't all clear both.
    private func clearAutoPause() {
        belowThresholdSince = nil
        guard isAutoPaused else { return }
        isAutoPaused = false
        // Guarded, so clearing an auto-pause can never restart the clock on a manually paused trip.
        if state == .running { startClock() }
    }

    /// Auto-pause is only ever entered on positive evidence — an accepted fix below the threshold — so
    /// it must be released once that evidence stops. `LocationManager` drops unusable-accuracy fixes,
    /// and accuracy often degrades *because* the phone is still, so without this a rider who auto-paused
    /// at a light and rode off through poor signal would never see a resume-speed fix: the clock stays
    /// frozen and that riding time vanishes. Silence isn't evidence of standing still, so fall back to
    /// counting time (as the trip did before auto-pause). If the rider really is stopped, the next
    /// usable fix re-arms the debounce and pauses again.
    private func releaseAutoPauseIfUnconfirmed() {
        guard isAutoPaused, let lastAcceptedFix else { return }
        guard now().timeIntervalSince(lastAcceptedFix) >= autoPauseFixTimeout else { return }
        clearAutoPause()
    }

    /// Decides whether a running trip should stop accumulating. Runs on the GPS clock
    /// (`location.timestamp`), not wall time, to match the `dt` used for distance. Safe only because
    /// `LocationManager` rejects fixes older than `maxFixAge`: a cached fix timestamped minutes ago
    /// would otherwise satisfy `autoPauseDelay` on its own and pause a moving rider instantly.
    private func updateAutoPause(for location: CLLocation) {
        guard settings.autoPauseEnabled else {
            clearAutoPause()
            return
        }
        // Negative speed is CoreLocation's "unknown" sentinel, not a slow one — hold state rather than
        // read it as a standstill.
        guard location.speed >= 0 else { return }

        if isAutoPaused {
            if location.speed >= autoResumeSpeed { clearAutoPause() }
            return
        }

        guard location.speed < autoPauseSpeed else {
            clearAutoPause() // moving: disarm the debounce
            return
        }
        let since = belowThresholdSince ?? location.timestamp
        belowThresholdSince = since
        if location.timestamp.timeIntervalSince(since) >= autoPauseDelay { beginAutoPause() }
    }

    /// Moves the point distance is measured from. Clears the rejection streak with it: the streak
    /// only ever means "the anchor looks wrong", which a new anchor settles.
    private func anchor(on location: CLLocation) {
        previousLocation = location
        teleportRejections = 0
    }

    private func consume(_ location: CLLocation) {
        // Wall-clock, not `location.timestamp`: this measures whether usable fixes are still arriving,
        // a fact about *now*, not about when the fix was taken.
        lastAcceptedFix = now()

        guard state == .running else {
            // Keep a fresh anchor while idle/paused so resuming never measures a large gap-distance.
            anchor(on: location)
            return
        }

        updateAutoPause(for: location)
        guard !isAutoPaused else {
            // As above: anchoring every fix keeps the standstill's GPS drift out of the total when the
            // rider pulls away.
            anchor(on: location)
            return
        }

        // Top speed from the instantaneous GPS reading, ignoring the negative "unknown" sentinel and
        // clamping teleport spikes with the same ceiling used for distance.
        if location.speed >= 0 {
            maxSpeed = max(maxSpeed, min(location.speed, maxPlausibleSpeed))
        }

        guard let previous = previousLocation else {
            anchor(on: location)
            if let altitude = location.usableAltitude(within: Self.maxAltitudeVerticalAccuracy) {
                altitudeProfile.append(AltitudeSample(distance: 0, altitude: altitude))
            }
            appendRouteSample(from: location)
            sampleElevation(from: location)
            return
        }

        let dt = location.timestamp.timeIntervalSince(previous.timestamp)
        guard dt > 0 else { return }

        let delta = location.distance(from: previous)
        guard delta / dt <= maxPlausibleSpeed else {
            // Likely a GPS teleport artifact: drop it and hold the anchor, so the next good fix is
            // measured from where the rider actually was. But once spikes pile up the anchor is what's
            // wrong (see `maxTeleportRejections`) — re-anchor and write off the gap rather than freeze the trip.
            teleportRejections += 1
            if teleportRejections >= maxTeleportRejections {
                anchor(on: location)
            }
            return
        }

        let advanced = delta > max(jitterFloor, 0.5 * location.horizontalAccuracy)
        if advanced {
            accumulatedDistance += delta
        }
        anchor(on: location)

        if let altitude = location.usableAltitude(within: Self.maxAltitudeVerticalAccuracy),
           accumulatedDistance - lastAltitudeSampleDistance >= altitudeSampleDistanceInterval {
            altitudeProfile.append(AltitudeSample(distance: accumulatedDistance, altitude: altitude))
            lastAltitudeSampleDistance = accumulatedDistance
        }

        // `routeSamples.isEmpty` isn't redundant with the first-fix branch above: a trip started while
        // the app was already tracking has an anchor from before `start()`, so its first *running* fix
        // comes through here — without this the track would begin 10 m in, planting the start marker down the road.
        if routeSamples.isEmpty || accumulatedDistance - lastRouteSampleDistance >= routeSampleDistanceInterval {
            appendRouteSample(from: location)
        }

        // Only a fix that moved the trip feeds elevation — the same jitter-floor protection distance
        // gets, applied to climb: GPS altitude wander and barometric drift at a red light must not
        // accumulate, and auto-pause can't guarantee that (the rider may switch it off).
        if advanced {
            sampleElevation(from: location)
        }
    }

    /// Records where the rider is, for the track. Unlike elevation sampling, this takes the fix with or
    /// without a usable altitude: a point with no height is still a point on the map, and GPX just omits
    /// its `<ele>`.
    private func appendRouteSample(from location: CLLocation) {
        routeSamples.append(RouteSample(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.usableAltitude(within: Self.maxAltitudeVerticalAccuracy),
            timestamp: location.timestamp
        ))
        lastRouteSampleDistance = accumulatedDistance
    }

    /// Reads the trip's altitude source — committed by `latchElevationSource(for:)` at the first sample
    /// — into the ascent/descent totals and grade window. Only reached by a fix that passed every guard
    /// above *and* advanced distance, the gating the elevation figures rely on (see `altimeter`).
    private func sampleElevation(from location: CLLocation) {
        let altitude: CLLocationDistance?
        switch elevationSource {
        case .barometer: altitude = altimeter.relativeAltitude
        case .gps: altitude = location.usableAltitude(within: Self.maxAltitudeVerticalAccuracy)
        case .undecided: altitude = latchElevationSource(for: location)
        }
        guard let altitude else { return }

        // A break in sampling separates two readings that aren't comparable — see
        // `elevationContinuityGap`. Anchor fresh and let the grade window refill.
        if let lastSample = lastElevationSampleTimestamp,
           location.timestamp.timeIntervalSince(lastSample) > Self.elevationContinuityGap {
            elevation.reanchor()
            grade.reset()
        }
        lastElevationSampleTimestamp = location.timestamp

        elevation.add(altitude: altitude)
        // The deadbanded totals move only on the rare fix that crosses the band; an identical rewrite
        // still invalidates every observer, so publish only on change.
        if totalAscent != elevation.ascent { totalAscent = elevation.ascent }
        if totalDescent != elevation.descent { totalDescent = elevation.descent }

        grade.add(distance: accumulatedDistance, altitude: altitude)
        let newGrade = grade.grade
        if currentGrade != newGrade { currentGrade = newGrade }
    }

    /// Commits the trip to barometer or GPS altitude from data actually arriving, not hardware presence:
    /// a barometer with denied Motion & Fitness permission reports available yet never delivers. The
    /// barometer gets a short grace for its first reading (it was only just started); GPS wins when there
    /// is no barometer, when it has failed (`AltimeterManager` folds errors into `isAvailable`), or when
    /// the grace runs out.
    private func latchElevationSource(for location: CLLocation) -> CLLocationDistance? {
        if altimeter.isAvailable, let reading = altimeter.relativeAltitude {
            elevationSource = .barometer
            elevation = ElevationAccumulator(deadband: Self.barometerDeadband)
            return reading
        }
        if altimeter.isAvailable, barometerGraceFixesRemaining > 0 {
            barometerGraceFixesRemaining -= 1
            return nil
        }
        elevationSource = .gps
        elevation = ElevationAccumulator(deadband: Self.gpsAltitudeDeadband)
        return location.usableAltitude(within: Self.maxAltitudeVerticalAccuracy)
    }
}
