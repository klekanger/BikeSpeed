import CoreLocation
import Foundation

/// One point of a trip's speed profile: how fast the rider was going at a given distance into the ride.
///
/// Unlike `AltitudeSample`, this is **never stored** — it's derived at view time from the recorded
/// `RouteSample` track by `SpeedProfile`, so it costs nothing in the trip blob and works retroactively on
/// trips saved before per-point speed was recorded. `distance` (accumulated metres, monotonic and
/// unaffected by pause gaps) is the X-axis, matching the height-profile chart it sits beside.
struct SpeedSample: Hashable, Sendable {
    let distance: CLLocationDistance // meters
    let speed: CLLocationSpeed // m/s
}
