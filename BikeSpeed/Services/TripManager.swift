import CoreLocation
import Combine
import Foundation

/// Owns the Start/Pause/Reset trip state machine and the distance/average-speed accumulation
/// derived from accepted location fixes. Elapsed active time is wall-clock based so it stays
/// correct across app backgrounding.
@MainActor
final class TripManager: ObservableObject {
    @Published private(set) var state: TripState = .idle
    @Published private(set) var accumulatedDistance: CLLocationDistance = 0 // meters
    @Published private(set) var elapsedActiveDuration: TimeInterval = 0
    @Published private(set) var maxSpeed: CLLocationSpeed = 0 // m/s, top instantaneous speed seen while running

    /// Whether a running trip has stopped accumulating because the rider is standing still. This is
    /// deliberately a flag on `.running` rather than a `TripState` case: a manual pause must stay
    /// distinguishable from an auto-pause (otherwise rolling forward would resume a trip the user
    /// paused on purpose), and `canSaveTrip` must not offer to save at every red light.
    @Published private(set) var isAutoPaused = false

    private var accumulatedActiveDuration: TimeInterval = 0
    private var activeStart: Date?
    private var previousLocation: CLLocation?
    /// Retained so the trip can call back into it: background location updates are requested for
    /// exactly the span of a recording — on at `start()`/`resume()`, off at `pause()`/`reset()`.
    /// An auto-pause deliberately does *not* release them: its only exit is a fix above the resume
    /// threshold, which can never arrive under a locked screen once GPS has been let go.
    private let locationSource: any LocationSource
    private var cancellable: AnyCancellable?
    /// The wall clock, injected. Everything here that asks "what time is it now" — as opposed to
    /// reading a fix's own `timestamp` — goes through this, so a test can drive elapsed time and the
    /// auto-pause watchdog without sleeping.
    private let now: @MainActor () -> Date
    /// Held strongly: subscribing to `settings.$autoPauseEnabled` retains only the publisher's
    /// subject, not the store, so without this the toggle would go silently inert wherever the
    /// caller doesn't happen to keep the store alive itself.
    private let settings: SettingsStore
    private var settingsCancellable: AnyCancellable?
    private var tickTimer: Timer?

    /// Set once in `start()` and never touched by `resume()`, unlike `activeStart` — this is the
    /// stable wall-clock start time saved into a `TripLogEntry`.
    private var tripStartDate: Date?
    private var altitudeSamples: [AltitudeSample] = []
    private var lastAltitudeSampleDistance: CLLocationDistance = 0
    private let altitudeSampleDistanceInterval: CLLocationDistance = 25 // meters

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
    private var autoPauseEnabled = true

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

    init(locationManager: any LocationSource, settings: SettingsStore, now: @escaping @MainActor () -> Date = { Date() }) {
        self.locationSource = locationManager
        self.settings = settings
        self.now = now
        autoPauseEnabled = settings.autoPauseEnabled
        // `@Published` fires from `willSet`, so the new value only arrives as the sink's argument —
        // re-reading `settings.autoPauseEnabled` here would still see the old one.
        settingsCancellable = settings.$autoPauseEnabled.sink { [weak self] enabled in
            self?.autoPauseEnabled = enabled
            if !enabled { self?.clearAutoPause() }
        }
        cancellable = locationManager.acceptedLocations.sink { [weak self] location in
            self?.consume(location)
        }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    /// The periodic work the trip clock drives: retire an auto-pause nothing is confirming any more,
    /// and republish elapsed time so a running trip's duration ticks up between fixes. Split out of the
    /// timer so it can be driven directly rather than waited on.
    func tick() {
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
    }

    func pause() {
        guard state == .running else { return }
        // Before `clearAutoPause()`, so it sees `.paused` and doesn't restart the clock: a manual
        // pause supersedes an auto-pause, and releasing it is now the user's call alone.
        state = .paused
        suspendClock()
        clearAutoPause()
        locationSource.setBackgroundUpdates(false)
    }

    func resume() {
        guard state == .paused else { return }
        startClock()
        state = .running
        locationSource.setBackgroundUpdates(true)
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
        state = .idle
        locationSource.setBackgroundUpdates(false)
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
            altitudeProfile: altitudeSamples
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
        guard autoPauseEnabled else {
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
            if location.verticalAccuracy >= 0 {
                altitudeSamples.append(AltitudeSample(distance: 0, altitude: location.altitude))
            }
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

        if delta > max(jitterFloor, 0.5 * location.horizontalAccuracy) {
            accumulatedDistance += delta
        }
        anchor(on: location)

        if location.verticalAccuracy >= 0,
           accumulatedDistance - lastAltitudeSampleDistance >= altitudeSampleDistanceInterval {
            altitudeSamples.append(AltitudeSample(distance: accumulatedDistance, altitude: location.altitude))
            lastAltitudeSampleDistance = accumulatedDistance
        }
    }
}
