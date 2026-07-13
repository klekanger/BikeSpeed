import CoreLocation
import Foundation

/// A saved, completed trip. All measurements are stored in SI units (meters, m/s, seconds),
/// matching the convention used throughout the model layer — the view layer converts via
/// `MeasurementSystem` for display, same as the live trip stats.
struct TripLogEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let startDate: Date
    let duration: TimeInterval // seconds, active duration only
    let distance: CLLocationDistance // meters
    let averageSpeed: CLLocationSpeed // m/s
    let maxSpeed: CLLocationSpeed // m/s
    let altitudeProfile: [AltitudeSample]
    /// Optional twice over. Semantically: a trip recorded without usable altitude data has no answer
    /// to "how much did you climb", and 0 would be indistinguishable from a genuinely flat ride.
    /// Structurally: `TripLogStore.load()` replaces an undecodable file with `[]` and the next save
    /// persists that — so a new field here must decode as absent from pre-v2 JSON, never fail.
    /// `TripLogStoreTests` pins both.
    let totalAscent: CLLocationDistance? // meters
    let totalDescent: CLLocationDistance? // meters, positive
}

/// One point of a trip's height profile. `distance` is the accumulated trip distance-so-far at
/// the moment this sample was taken (not a timestamp), since it's monotonic and unaffected by
/// pause gaps — the natural X-axis for an elevation chart.
struct AltitudeSample: Codable, Hashable {
    let distance: CLLocationDistance // meters
    let altitude: CLLocationDistance // meters
}
