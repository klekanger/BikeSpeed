import CoreLocation
import Foundation

/// One point of a trip's height profile.
///
/// `distance` is the accumulated trip distance-so-far at the moment the sample was taken (not a timestamp),
/// since it is monotonic and unaffected by pause gaps — the natural X-axis for an elevation chart.
///
/// Stored as a JSON blob on `StoredTrip.altitudeData` rather than inline in `TripLogEntry`: only the detail
/// view's chart ever reads a profile, so the trip list must not pay to decode one per row. Unlike
/// `RouteSample`, it carries no timestamp — a chart against distance has no use for one.
struct AltitudeSample: Codable, Hashable, Sendable {
    let distance: CLLocationDistance // meters
    let altitude: CLLocationDistance // meters
}
