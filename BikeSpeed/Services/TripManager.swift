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

    private var accumulatedActiveDuration: TimeInterval = 0
    private var activeStart: Date?
    private var previousLocation: CLLocation?
    private var cancellable: AnyCancellable?
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

    var averageSpeed: Double { // m/s
        let duration = currentElapsedActiveDuration()
        guard duration > 0 else { return 0 }
        return accumulatedDistance / duration
    }

    init(locationManager: LocationManager) {
        cancellable = locationManager.acceptedLocations.sink { [weak self] location in
            self?.consume(location)
        }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.state == .running else { return }
                self.elapsedActiveDuration = self.currentElapsedActiveDuration()
            }
        }
    }

    func start() {
        guard state == .idle else { return }
        state = .running
        activeStart = Date()
        tripStartDate = Date()
    }

    func pause() {
        guard state == .running else { return }
        accumulatedActiveDuration += Date().timeIntervalSince(activeStart ?? Date())
        activeStart = nil
        state = .paused
        elapsedActiveDuration = accumulatedActiveDuration
    }

    func resume() {
        guard state == .paused else { return }
        activeStart = Date()
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

    private func currentElapsedActiveDuration() -> TimeInterval {
        accumulatedActiveDuration + (state == .running ? Date().timeIntervalSince(activeStart ?? Date()) : 0)
    }

    private func consume(_ location: CLLocation) {
        guard state == .running else {
            // Keep a fresh anchor while idle/paused so resuming never measures a large gap-distance.
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
