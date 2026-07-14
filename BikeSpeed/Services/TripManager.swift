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
    private(set) var maxSpeed: CLLocationSpeed = 0 // m/s, top instantaneous speed seen while running

    /// Nil until any usable altitude has been sampled: "no data" must stay distinguishable from "a
    /// flat ride" in the live UI just as it is in the saved log (see `TripLogEntry`).
    private(set) var totalAscent: CLLocationDistance? // meters
    private(set) var totalDescent: CLLocationDistance? // meters, positive
    /// Rise over a trailing ~30 m of run — e.g. 0.05 for a 5 % climb. Nil until enough of the trip
    /// has been ridden to measure one honestly; see `GradeCalculator`.
    private(set) var currentGrade: Double?

    /// Whether a running trip has stopped accumulating because the rider is standing still. This is
    /// deliberately a flag on `.running` rather than a `TripState` case: a manual pause must stay
    /// distinguishable from an auto-pause (otherwise rolling forward would resume a trip the user
    /// paused on purpose), and `canSaveTrip` must not offer to save at every red light.
    private(set) var isAutoPaused = false

    private var accumulatedActiveDuration: TimeInterval = 0
    private var activeStart: Date?
    private var previousLocation: CLLocation?
    /// Retained so the trip can call back into it: background location updates are requested for
    /// exactly the span of a recording — on at `start()`/`resume()`, off at `pause()`/`reset()`.
    /// An auto-pause deliberately does *not* release them: its only exit is a fix above the resume
    /// threshold, which can never arrive under a locked screen once GPS has been let go.
    private let locationSource: any LocationSource
    @ObservationIgnored private var cancellable: AnyCancellable?
    /// The wall clock, injected. Everything here that asks "what time is it now" — as opposed to
    /// reading a fix's own `timestamp` — goes through this, so a test can drive elapsed time and the
    /// auto-pause watchdog without sleeping.
    private let now: @MainActor () -> Date
    /// Read directly wherever auto-pause is decided, rather than mirrored into a local flag off a
    /// subscription. Under `@Observable` there is no `$autoPauseEnabled` publisher to sink, and there
    /// no longer needs to be: a plain read always sees the current value, which is what the mirror was
    /// only ever approximating. See `tick()` for the one case a read alone doesn't cover.
    private let settings: SettingsStore
    @ObservationIgnored private var tickTimer: Timer?

    /// Set once in `start()` and never touched by `resume()`, unlike `activeStart` — this is the
    /// stable wall-clock start time saved into a `TripLogEntry`.
    private var tripStartDate: Date?
    private var altitudeSamples: [AltitudeSample] = []
    private var lastAltitudeSampleDistance: CLLocationDistance = 0
    private let altitudeSampleDistanceInterval: CLLocationDistance = 25 // meters

    /// The trip's recorded track, for the detail map and the GPX export. Decimated by distance like
    /// `altitudeSamples`, but far more finely: the height profile only needs its shape, whereas a
    /// track sampled every 25 m visibly cuts corners on a map and exports as a ride nobody rode.
    /// `@ObservationIgnored` — nothing draws it live, and waking observers for a growing array every
    /// few seconds would invalidate the gauge for no one's benefit. `TripControlBar` reads it once,
    /// at Save, which is not a body read and so needs no tracking.
    @ObservationIgnored private(set) var routeSamples: [RouteSample] = []
    private var lastRouteSampleDistance: CLLocationDistance = 0
    private let routeSampleDistanceInterval: CLLocationDistance = 10 // meters

    /// The barometer. Ascent/descent and grade are *sampled* from it at each accepted fix that
    /// advanced the trip's distance, rather than accumulated on a subscription of its own, so they
    /// inherit `consume(_:)`'s running and auto-pause gating for free — and a standstill, where
    /// barometric pressure drift and GPS altitude wander read as climb, samples nothing at all.
    private let altimeter: any AltitudeSource
    /// Which altitude source this trip is committed to. Latched once per trip from data actually
    /// arriving (see `latchElevationSource(for:)`): hardware presence alone can't decide — a
    /// barometer whose Motion & Fitness permission was denied reports available yet never delivers —
    /// and the two sources measure against different zero points, so switching mid-trip would bank
    /// the difference between them as a phantom climb.
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
    /// GPS altitude carries its own error bar; beyond this it is real but useless — a 30 m error
    /// against a 3 m deadband manufactures climb out of thin air — so such fixes contribute nothing.
    private static let maxAltitudeVerticalAccuracy: CLLocationAccuracy = 15
    /// How many fixes an undecided trip waits on the just-started barometer's first reading before
    /// settling for GPS altitude. Readings normally arrive within a second or two of
    /// `startUpdates()`, and a denied permission flips `isAvailable` instead, so this only decides
    /// the pathological silent case.
    private static let barometerLatchGraceFixes = 10
    /// A gap in sampling longer than this — a pause, a standstill, a stretch of unusable fixes —
    /// separates two readings that aren't comparable: whatever altitude did in between wasn't
    /// ridden. The next sample re-baselines instead of banking the gap (see `sampleElevation`).
    private static let elevationContinuityGap: TimeInterval = 15

    /// Guards against GPS teleport artifacts corrupting the trip total.
    private let maxPlausibleSpeed: CLLocationSpeed = 120 / 3.6 // ~120 km/h in m/s
    private let jitterFloor: CLLocationDistance = 1.0
    /// How many implausible fixes in a row to reject before concluding the anchor is the bad one.
    /// The teleport guard can't tell which of the two locations is the artifact, so it assumes the
    /// new fix is — correct for an isolated GPS spike. But if `previousLocation` is the outlier
    /// (one bad fix that got anchored, or a jump while the signal was out), every later fix measures
    /// an implausible speed against it and is dropped, and since a dropped fix doesn't advance the
    /// anchor, distance stops accumulating for the rest of the ride with only Reset to clear it.
    /// A genuine spike is a single fix, so a streak means the anchor is what's wrong: re-anchor and
    /// write off the gap, costing at most this many fixes of distance instead of the whole trip.
    private let maxTeleportRejections = 3
    private var teleportRejections = 0

    /// Auto-pause thresholds. The resume threshold sits deliberately above the pause threshold:
    /// GPS speed drifts around 0–1.5 km/h at a standstill, so a single cutoff would flap on and off.
    /// Pausing has to wait out `autoPauseDelay`, but resuming is immediate, so no moving time or
    /// distance is lost pulling away from a light.
    private let autoPauseSpeed: CLLocationSpeed = 2 / 3.6 // 2 km/h in m/s
    private let autoResumeSpeed: CLLocationSpeed = 3 / 3.6 // 3 km/h in m/s
    private let autoPauseDelay: TimeInterval = 3
    /// How long an auto-pause may survive without a single accepted fix to justify it. Fixes arrive
    /// about once a second (`kCLDistanceFilterNone`), so anything near this gap means the signal
    /// went unusable, not that the rider is holding still. See `releaseAutoPauseIfUnconfirmed()`.
    private let autoPauseFixTimeout: TimeInterval = 5
    private var belowThresholdSince: Date?
    private var lastAcceptedFix: Date?

    var averageSpeed: Double { // m/s
        let duration = currentElapsedActiveDuration()
        guard duration > 0 else { return 0 }
        return accumulatedDistance / duration
    }

    /// Whether `makeLogEntry()` would currently succeed — used to gate the Save button so it's
    /// only enabled when there's actually something meaningful to save.
    var canSaveTrip: Bool {
        state == .paused && accumulatedActiveDuration >= 5 && accumulatedDistance >= 10
    }

    /// Whether `reset()` would actually clear anything — used to gate the Reset button. A trip is
    /// resettable exactly while it is manually paused: mid-ride it must not be wiped out from under
    /// the rider (and an auto-pause is still mid-ride), while an idle trip is already at zero, so
    /// offering Reset there — as it did straight after a reset — is a button that does nothing when
    /// tapped. No distance or duration floor, unlike `canSaveTrip`: clearing a false start too short
    /// to be worth saving is precisely what Reset is for.
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
        // The timer is scheduled from the main actor, so its block fires on the main run loop;
        // asserting that isolation keeps `tick()` synchronous instead of hopping through a `Task`.
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    /// The periodic work the trip clock drives: retire an auto-pause nothing is confirming any more,
    /// and republish elapsed time so a running trip's duration ticks up between fixes. Split out of the
    /// timer so it can be driven directly rather than waited on.
    func tick() {
        // Switching auto-pause off must release one that is already active, and the trip clock is the
        // only place that can see it happen. `updateAutoPause(for:)` reads the setting too, but it runs
        // on accepted fixes — and a rider who is auto-paused is, by definition, standing still, so there
        // may be no next fix to notice the change at. This is the job the old `settings.$autoPauseEnabled`
        // sink did; at 0.5 s, a toggle flipped in a sheet still feels instant.
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
        // Before `clearAutoPause()`, so it sees `.paused` and doesn't restart the clock: a manual
        // pause supersedes an auto-pause, and releasing it is now the user's call alone.
        state = .paused
        suspendClock()
        clearAutoPause()
        locationSource.setBackgroundUpdates(false)
        altimeter.stopUpdates()
        // A parked bike isn't on a slope; the reading would otherwise assert the last hill all pause.
        currentGrade = nil
    }

    func resume() {
        guard state == .paused else { return }
        startClock()
        state = .running
        locationSource.setBackgroundUpdates(true)
        altimeter.startUpdates()
        // Whatever altitude did across the pause wasn't ridden — and the restarted barometer rebases
        // its zero anyway — so neither reference point survives: re-baseline rather than bank the
        // difference as climb. (The sampling-gap rule in `sampleElevation` also catches this, but a
        // short pause with a rebased barometer would slip under it.)
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
        altitudeSamples.removeAll()
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

    /// Snapshots the current trip into a saveable log entry. `nil` if there's no paused trip to
    /// save, or if the trip is too short/short-lived to be meaningful.
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
            altitudeProfile: altitudeSamples,
            // Already nil when no fix ever carried a usable altitude: "we don't know" must stay
            // distinguishable from "it was flat". See `TripLogEntry`.
            totalAscent: totalAscent,
            totalDescent: totalDescent
        )
    }

    /// `activeStart` is non-nil exactly while the clock is running — that is, not idle, not manually
    /// paused and not auto-paused — so these two are the only places the wall-clock total is folded
    /// up, shared by both kinds of pause.
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
        // Standing still, there is no current slope — without this the readout would keep asserting
        // the last hill for the whole stop.
        currentGrade = nil
    }

    /// The one place auto-pause is unwound. Auto-pause is two pieces of state — the `isAutoPaused`
    /// flag and the `belowThresholdSince` debounce that arms it — and every exit clears both here:
    /// a manual pause, a reset, the setting going off, a fix at resume speed, the fix-loss watchdog,
    /// and simply moving again. Owning both together is the point: they were previously cleared in
    /// five places that didn't all clear both, and the debounce only stayed consistent because the
    /// disabled-guard happened to re-clear it on every fix.
    private func clearAutoPause() {
        belowThresholdSince = nil
        guard isAutoPaused else { return }
        isAutoPaused = false
        // Guarded, so clearing an auto-pause can never restart the clock on a manually paused trip.
        if state == .running { startClock() }
    }

    /// An auto-pause is only ever *entered* on positive evidence — an accepted fix reporting a speed
    /// below the threshold — so it must also be released once that evidence stops arriving.
    /// `LocationManager` drops fixes whose accuracy is unusable, and accuracy commonly degrades
    /// precisely because the phone is sitting still, so without this a rider who auto-paused at a
    /// light and then rode off through a poor-signal stretch would never see a fix above the resume
    /// threshold: the clock would stay frozen and that riding time would vanish from the trip.
    /// Silence is not evidence of standing still, so fall back to counting the time — which is what
    /// the trip did before auto-pause existed. If the rider really is stopped, the next usable fix
    /// re-arms the debounce and pauses again.
    private func releaseAutoPauseIfUnconfirmed() {
        guard isAutoPaused, let lastAcceptedFix else { return }
        guard now().timeIntervalSince(lastAcceptedFix) >= autoPauseFixTimeout else { return }
        clearAutoPause()
    }

    /// Decides whether a running trip should stop accumulating. Runs on the GPS clock
    /// (`location.timestamp`) rather than wall time, to stay consistent with the `dt` used for
    /// distance below. That is only safe because `LocationManager` rejects fixes older than its
    /// `maxFixAge`: a cached fix carrying a timestamp minutes in the past would otherwise satisfy
    /// `autoPauseDelay` on its own and pause a moving rider instantly, debounce and all.
    private func updateAutoPause(for location: CLLocation) {
        guard settings.autoPauseEnabled else {
            clearAutoPause()
            return
        }
        // A negative speed is CoreLocation's "unknown" sentinel, not a slow one — hold the current
        // state rather than reading it as a standstill.
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
        // Wall-clock, not `location.timestamp`: this measures whether usable fixes are still
        // arriving, which is a fact about *now*, not about when the fix was taken.
        lastAcceptedFix = now()

        guard state == .running else {
            // Keep a fresh anchor while idle/paused so resuming never measures a large gap-distance.
            anchor(on: location)
            return
        }

        updateAutoPause(for: location)
        guard !isAutoPaused else {
            // Same reasoning as above: anchoring on every fix keeps the standstill's GPS drift from
            // landing in the total as distance the moment the rider pulls away.
            anchor(on: location)
            return
        }

        // Track top speed from the instantaneous GPS reading, ignoring the negative "unknown"
        // sentinel and clamping obvious teleport spikes with the same ceiling used for distance.
        if location.speed >= 0 {
            maxSpeed = max(maxSpeed, min(location.speed, maxPlausibleSpeed))
        }

        guard let previous = previousLocation else {
            anchor(on: location)
            if let altitude = location.usableAltitude(within: Self.maxAltitudeVerticalAccuracy) {
                altitudeSamples.append(AltitudeSample(distance: 0, altitude: altitude))
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
            // still measured from a place the rider actually was. But a spike is a single fix — once
            // they pile up it's the anchor that's wrong, and holding it would freeze distance for the
            // rest of the ride. Re-anchor and write off the gap rather than the trip.
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
            altitudeSamples.append(AltitudeSample(distance: accumulatedDistance, altitude: altitude))
            lastAltitudeSampleDistance = accumulatedDistance
        }

        // `routeSamples.isEmpty` is not redundant with the first-fix branch above: a trip started while
        // the app was already tracking has an anchor from before `start()`, so its first *running* fix
        // comes through here — and without this the track would begin 10 m into the ride, putting the
        // start marker down the road from where the rider actually set off.
        if routeSamples.isEmpty || accumulatedDistance - lastRouteSampleDistance >= routeSampleDistanceInterval {
            appendRouteSample(from: location)
        }

        // Only a fix that moved the trip feeds elevation: the jitter floor freezes distance at a
        // standstill, and this is the same protection for climb — GPS altitude wander and barometric
        // drift at a red light must not accumulate, and auto-pause alone can't guarantee that
        // (it is a setting the rider may switch off).
        if advanced {
            sampleElevation(from: location)
        }
    }

    /// Records where the rider is, for the track. Unlike the elevation sampling below, this takes the
    /// fix whether or not it carried a usable altitude: a point with no height is still a point on the
    /// map, and GPX just omits its `<ele>`.
    private func appendRouteSample(from location: CLLocation) {
        routeSamples.append(RouteSample(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.usableAltitude(within: Self.maxAltitudeVerticalAccuracy),
            timestamp: location.timestamp
        ))
        lastRouteSampleDistance = accumulatedDistance
    }

    /// Reads the trip's altitude source — committed by `latchElevationSource(for:)` at the first
    /// sample — into the ascent/descent totals and the grade window. Only reached by a fix that
    /// passed every guard above *and* advanced the distance, which is the gating the elevation
    /// figures rely on (see `altimeter`).
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
        // The deadbanded totals move on the rare fix that crosses the band, but an identical rewrite
        // still invalidates every observer — publish only change.
        if totalAscent != elevation.ascent { totalAscent = elevation.ascent }
        if totalDescent != elevation.descent { totalDescent = elevation.descent }

        grade.add(distance: accumulatedDistance, altitude: altitude)
        let newGrade = grade.grade
        if currentGrade != newGrade { currentGrade = newGrade }
    }

    /// Commits the trip to barometer or GPS altitude from data actually arriving, not from hardware
    /// presence: a barometer whose Motion & Fitness permission was denied reports available yet
    /// never delivers a reading. The barometer gets a short grace to produce its first reading — it
    /// was only started with the trip — and GPS wins when there is no barometer, when it has failed
    /// (`AltimeterManager` folds update errors into `isAvailable`), or when the grace runs out.
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
