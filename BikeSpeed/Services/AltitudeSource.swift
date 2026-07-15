import Foundation

/// What `TripManager` needs from the barometer: whether one is delivering, its latest reading, and a
/// lifecycle matched to the trip's. There is nothing to subscribe to — the trip *samples*
/// `relativeAltitude` at each accepted GPS fix (see `consume(_:)`), so ascent inherits the
/// running/auto-pause gating that already guards distance. `AltimeterManager` is the real
/// implementation; tests substitute a fake and set the reading by hand.
@MainActor
protocol AltitudeSource: AnyObject {
    /// False where there is no barometer (notably the Simulator) — or where there effectively is
    /// none: `AltimeterManager` drops this once updates start erroring, which is how a denied
    /// Motion & Fitness permission presents. The trip then falls back to GPS altitude with a wider
    /// deadband instead of waiting forever on readings that will never come.
    var isAvailable: Bool { get }
    /// Meters relative to where updates started; nil until the first reading arrives, and nil again
    /// after `stopUpdates()`. Only deltas are ever consumed, so the arbitrary zero point never matters.
    var relativeAltitude: Double? { get }
    /// The barometer runs for exactly the span of a recording — on at `start()`/`resume()`, off at
    /// `pause()`/`reset()`, mirroring background location updates — so the Motion permission prompt
    /// belongs to the first trip rather than to app launch, and the sensor isn't held hot while the
    /// app sits idle.
    func startUpdates()
    func stopUpdates()
}
