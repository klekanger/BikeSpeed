import Foundation

/// What `TripManager` needs from the barometer: whether one exists, and its latest reading. There is
/// nothing to subscribe to — the trip *samples* altitude at each accepted GPS fix (see `consume(_:)`),
/// so ascent inherits the running/auto-pause gating that already guards distance. `AltimeterManager`
/// is the real implementation; tests substitute a fake and set the reading by hand.
@MainActor
protocol AltitudeSource: AnyObject {
    /// False where there is no barometer (notably the Simulator) — the trip then falls back to GPS
    /// altitude with a wider deadband.
    var isAvailable: Bool { get }
    /// Meters relative to where updates started; nil until the first reading arrives. Only deltas
    /// are ever consumed, so the arbitrary zero point never matters.
    var relativeAltitude: Double? { get }
}
