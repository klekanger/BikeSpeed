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
    private var cancellable: AnyCancellable?
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

    init(locationManager: LocationManager, settings: SettingsStore) {
        self.settings = settings
        autoPauseEnabled = settings.autoPauseEnabled
        // `@Published` fires from `willSet`, so the new value only arrives as the sink's argument —
        // re-reading `settings.autoPauseEnabled` here would still see the old one.
        settingsCancellable = settings.$autoPauseEnabled.sink { [weak self] enabled in
            self?.autoPauseEnabled = enabled
            if !enabled { self?.endAutoPause() }
        }
        cancellable = locationManager.acceptedLocations.sink { [weak self] location in
            self?.consume(location)
        }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.releaseAutoPauseIfUnconfirmed()
                guard self.activeStart != nil else { return }
                self.elapsedActiveDuration = self.currentElapsedActiveDuration()
            }
        }
    }

    func start() {
        guard state == .idle else { return }
        state = .running
        startClock()
        tripStartDate = Date()
    }

    func pause() {
        guard state == .running else { return }
        suspendClock()
        // A manual pause supersedes an auto-pause, so releasing it is the user's call alone.
        isAutoPaused = false
        belowThresholdSince = nil
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        startClock()
        state = .running
    }

    func reset() {
        guard state == .idle || state == .paused else { return }
        accumulatedDistance = 0
        accumulatedActiveDuration = 0
        elapsedActiveDuration = 0
        maxSpeed = 0
        activeStart = nil
        previousLocation = nil
        tripStartDate = nil
        isAutoPaused = false
        belowThresholdSince = nil
        lastAcceptedFix = nil
        altitudeSamples.removeAll()
        lastAltitudeSampleDistance = 0
        state = .idle
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
        activeStart = Date()
    }

    private func suspendClock() {
        guard let activeStart else { return } // already stopped; folding again would double-count
        accumulatedActiveDuration += Date().timeIntervalSince(activeStart)
        self.activeStart = nil
        elapsedActiveDuration = accumulatedActiveDuration
    }

    private func currentElapsedActiveDuration() -> TimeInterval {
        accumulatedActiveDuration + (activeStart.map { Date().timeIntervalSince($0) } ?? 0)
    }

    private func beginAutoPause() {
        isAutoPaused = true
        suspendClock()
    }

    private func endAutoPause() {
        guard isAutoPaused else { return }
        isAutoPaused = false
        belowThresholdSince = nil
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
        guard Date().timeIntervalSince(lastAcceptedFix) >= autoPauseFixTimeout else { return }
        endAutoPause()
    }

    /// Decides whether a running trip should stop accumulating. Runs on the GPS clock
    /// (`location.timestamp`) rather than wall time, to stay consistent with the `dt` used for
    /// distance below. That is only safe because `LocationManager` rejects fixes older than its
    /// `maxFixAge`: a cached fix carrying a timestamp minutes in the past would otherwise satisfy
    /// `autoPauseDelay` on its own and pause a moving rider instantly, debounce and all.
    private func updateAutoPause(for location: CLLocation) {
        guard autoPauseEnabled else {
            endAutoPause()
            belowThresholdSince = nil
            return
        }
        // A negative speed is CoreLocation's "unknown" sentinel, not a slow one — hold the current
        // state rather than reading it as a standstill.
        guard location.speed >= 0 else { return }

        if isAutoPaused {
            if location.speed >= autoResumeSpeed { endAutoPause() }
            return
        }

        guard location.speed < autoPauseSpeed else {
            belowThresholdSince = nil
            return
        }
        let since = belowThresholdSince ?? location.timestamp
        belowThresholdSince = since
        if location.timestamp.timeIntervalSince(since) >= autoPauseDelay { beginAutoPause() }
    }

    private func consume(_ location: CLLocation) {
        // Wall-clock, not `location.timestamp`: this measures whether usable fixes are still
        // arriving, which is a fact about *now*, not about when the fix was taken.
        lastAcceptedFix = Date()

        guard state == .running else {
            // Keep a fresh anchor while idle/paused so resuming never measures a large gap-distance.
            previousLocation = location
            return
        }

        updateAutoPause(for: location)
        guard !isAutoPaused else {
            // Same reasoning as above: anchoring on every fix keeps the standstill's GPS drift from
            // landing in the total as distance the moment the rider pulls away.
            previousLocation = location
            return
        }

        // Track top speed from the instantaneous GPS reading, ignoring the negative "unknown"
        // sentinel and clamping obvious teleport spikes with the same ceiling used for distance.
        if location.speed >= 0 {
            maxSpeed = max(maxSpeed, min(location.speed, maxPlausibleSpeed))
        }

        guard let previous = previousLocation else {
            previousLocation = location
            if location.verticalAccuracy >= 0 {
                altitudeSamples.append(AltitudeSample(distance: 0, altitude: location.altitude))
            }
            return
        }

        let dt = location.timestamp.timeIntervalSince(previous.timestamp)
        guard dt > 0 else { return }

        let delta = location.distance(from: previous)
        guard delta / dt <= maxPlausibleSpeed else {
            // Likely a GPS teleport artifact — don't accumulate or advance the anchor.
            return
        }

        if delta > max(jitterFloor, 0.5 * location.horizontalAccuracy) {
            accumulatedDistance += delta
        }
        previousLocation = location

        if location.verticalAccuracy >= 0,
           accumulatedDistance - lastAltitudeSampleDistance >= altitudeSampleDistanceInterval {
            altitudeSamples.append(AltitudeSample(distance: accumulatedDistance, altitude: location.altitude))
            lastAltitudeSampleDistance = accumulatedDistance
        }
    }
}
