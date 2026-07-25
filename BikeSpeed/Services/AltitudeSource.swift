import Foundation

/// What `TripManager` needs from the barometer: whether one is delivering, its latest reading, and a
/// lifecycle matched to the trip's. Nothing to subscribe to — the trip *samples* `relativeAltitude` at
/// each accepted GPS fix (see `consume(_:)`), so ascent inherits the running/auto-pause gating that
/// guards distance. `AltimeterManager` is the real implementation; tests substitute a fake.
@MainActor
protocol AltitudeSource: AnyObject {
    /// False where there is no barometer (notably the Simulator), or effectively none: `AltimeterManager`
    /// drops this once updates start erroring, which is how a denied Motion & Fitness permission presents.
    /// The trip then falls back to GPS altitude with a wider deadband instead of waiting forever.
    var isAvailable: Bool { get }
    /// Meters relative to where updates started; nil until the first reading, nil again after
    /// `stopUpdates()`. Only deltas are consumed, so the arbitrary zero point never matters.
    var relativeAltitude: Double? { get }
    /// Runs for exactly the span of a recording — on at `start()`/`resume()`, off at `pause()`/`reset()`,
    /// mirroring background location updates — so the Motion prompt belongs to the first trip, not app
    /// launch, and the sensor isn't held hot while idle.
    func startUpdates()
    func stopUpdates()
}
