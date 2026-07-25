import CoreLocation
import Foundation

/// A saved, completed trip — the *scalar* summary of one. All measurements in SI units (meters, m/s,
/// seconds), like the rest of the model layer; the view layer converts via `MeasurementSystem` for display.
///
/// The domain value, not the row: `StoredTrip` is what SwiftData persists, this is what the pure code speaks
/// — what `TripLogSummary` reduces, what the list draws, and (being `Codable`) what a future web service
/// would put on the wire unchanged.
///
/// **The heavy per-trip payloads are deliberately not here.** The height profile and track are
/// hundreds-to-thousands of samples each and the list draws neither; they live as blobs on `StoredTrip`,
/// loaded off the main actor only when a trip's detail opens. Folding either back in would put every trip's
/// payload into every render of the list.
struct TripLogEntry: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let startDate: Date
    let duration: TimeInterval // seconds, active duration only
    let distance: CLLocationDistance // meters
    let averageSpeed: CLLocationSpeed // m/s
    let maxSpeed: CLLocationSpeed // m/s
    /// Nil, not zero: a trip without usable altitude data has no answer to "how much did you climb", and 0
    /// would be indistinguishable from a genuinely flat ride.
    let totalAscent: CLLocationDistance? // meters
    let totalDescent: CLLocationDistance? // meters, positive
}
